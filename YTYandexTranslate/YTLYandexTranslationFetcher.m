#import "YTLYandexTranslationFetcher.h"
#import <CommonCrypto/CommonCrypto.h>

#define YANDEX_API_HOST @"api.browser.yandex.ru"
#define YANDEX_HMAC_KEY @"bt8xH3VOlb4mqf0nqAibnDOoiPlXsisf"
#define YANDEX_COMPONENT_VERSION @"25.6.0.2259"
#define YANDEX_USER_AGENT @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 YaBrowser/25.4.0.0 Safari/537.36"

@interface YTLYandexTranslationFetcher ()
@property (nonatomic, strong) NSString *sessionUUID;
@property (nonatomic, strong) NSString *sessionSecretKey;
@property (nonatomic, assign) NSTimeInterval sessionExpiresAt;
@property (nonatomic, strong) NSURLSession *urlSession;
@end

@implementation YTLYandexTranslationFetcher

+ (instancetype)sharedInstance {
    static YTLYandexTranslationFetcher *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        _urlSession = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - HMAC Utilities

+ (NSString *)hmacSha256SignatureForData:(NSData *)data {
    const char *cKey  = [YANDEX_HMAC_KEY cStringUsingEncoding:NSUTF8StringEncoding];
    unsigned char cHMAC[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), [data bytes], [data length], cHMAC);
    
    NSMutableString *hexString = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hexString appendFormat:@"%02x", cHMAC[i]];
    }
    return [hexString copy];
}

+ (NSString *)generateUUID {
    NSString *hexDigits = @"0123456789ABCDEF";
    NSMutableString *uuid = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 32; i++) {
        uint32_t randomDigit = arc4random_uniform(16);
        [uuid appendFormat:@"%C", [hexDigits characterAtIndex:randomDigit]];
    }
    return [uuid copy];
}

#pragma mark - Protobuf Encoding

static void appendVarint(NSMutableData *data, uint64_t value) {
    do {
        uint8_t byte = value & 0x7F;
        value >>= 7;
        if (value > 0) {
            byte |= 0x80;
        }
        [data appendBytes:&byte length:1];
    } while (value > 0);
}

static void appendString(NSMutableData *data, uint32_t tag, NSString *str) {
    if (!str || str.length == 0) return;
    NSData *strBytes = [str dataUsingEncoding:NSUTF8StringEncoding];
    appendVarint(data, (tag << 3) | 2);
    appendVarint(data, strBytes.length);
    [data appendData:strBytes];
}

static void appendDouble(NSMutableData *data, uint32_t tag, double val) {
    if (val == 0) return;
    appendVarint(data, (tag << 3) | 1);
    [data appendBytes:&val length:8];
}

static void appendInt32(NSMutableData *data, uint32_t tag, int32_t val) {
    if (val == 0) return;
    appendVarint(data, (tag << 3) | 0);
    appendVarint(data, val);
}

static void appendBool(NSMutableData *data, uint32_t tag, BOOL val) {
    if (!val) return;
    appendVarint(data, (tag << 3) | 0);
    appendVarint(data, 1);
}

#pragma mark - Protobuf Decoding

static uint64_t readVarint(NSData *data, NSUInteger *offset) {
    uint64_t value = 0;
    int shift = 0;
    const uint8_t *bytes = data.bytes;
    while (*offset < data.length) {
        uint8_t b = bytes[*offset];
        (*offset)++;
        value |= (uint64_t)(b & 0x7F) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
    }
    return value;
}

static NSString *readString(NSData *data, NSUInteger *offset) {
    uint64_t length = readVarint(data, offset);
    if (*offset + length > data.length) return nil;
    NSString *str = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(*offset, length)] encoding:NSUTF8StringEncoding];
    *offset += length;
    return str;
}

/*
static double readDouble(NSData *data, NSUInteger *offset) {
    if (*offset + 8 > data.length) return 0;
    double val;
    [data getBytes:&val range:NSMakeRange(*offset, 8)];
    *offset += 8;
    return val;
}
*/

#pragma mark - Networking

- (void)fetchSessionWithCompletion:(void(^)(NSError *error))completion {
    if (self.sessionSecretKey && [[NSDate date] timeIntervalSince1970] < self.sessionExpiresAt) {
        if (completion) completion(nil);
        return;
    }
    
    NSString *uuid = [YTLYandexTranslationFetcher generateUUID];
    
    // YandexSessionRequest
    NSMutableData *body = [NSMutableData data];
    appendString(body, 1, uuid); // uuid
    appendString(body, 2, @"video-translation"); // module
    
    NSString *signature = [YTLYandexTranslationFetcher hmacSha256SignatureForData:body];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@/session/create", YANDEX_API_HOST]]];
    req.HTTPMethod = @"POST";
    [req setValue:YANDEX_USER_AGENT forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/x-protobuf" forHTTPHeaderField:@"Accept"];
    [req setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];
    [req setValue:signature forHTTPHeaderField:@"Vtrans-Signature"];
    req.HTTPBody = body;
    
    [[self.urlSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            if (completion) completion(error ?: [NSError errorWithDomain:@"VOTError" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Networking error"}]);
            return;
        }
        
        NSUInteger offset = 0;
        NSString *secretKey = nil;
        // uint64_t expires = 0;
        
        while (offset < data.length) {
            uint64_t tagAndType = readVarint(data, &offset);
            int tag = tagAndType >> 3;
            int type = tagAndType & 7;
            
            if (tag == 1 && type == 2) {
                secretKey = readString(data, &offset);
            } else if (tag == 2 && type == 0) {
                // expires = readVarint(data, &offset);
                readVarint(data, &offset);
            } else {
                if (type == 0) readVarint(data, &offset);
                else if (type == 1) offset += 8;
                else if (type == 2) offset += readVarint(data, &offset);
                else if (type == 5) offset += 4;
            }
        }
        
        if (secretKey) {
            self.sessionUUID = uuid;
            self.sessionSecretKey = secretKey;
            self.sessionExpiresAt = [[NSDate date] timeIntervalSince1970] + 3600; // rough expiry
            if (completion) completion(nil);
        } else {
            if (completion) completion([NSError errorWithDomain:@"VOTError" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse session"}]);
        }
    }] resume];
}

- (void)requestTranslationForVideoID:(NSString *)videoID
                            duration:(NSTimeInterval)duration
                   completionHandler:(void(^)(NSURL *audioURL, NSError *error))completion {
    [self fetchSessionWithCompletion:^(NSError *error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        
        NSString *videoURLString = [NSString stringWithFormat:@"https://youtu.be/%@", videoID];
        
        // VideoTranslationRequest payload
        NSMutableData *body = [NSMutableData data];
        appendString(body, 3, videoURLString); // url
        appendBool(body, 5, YES); // firstRequest
        appendDouble(body, 6, duration); // duration
        appendInt32(body, 7, 1); // unknown0=1
        appendString(body, 8, @"en"); // language=en (assuming source is english for now)
        appendBool(body, 9, NO); // forceSourceLang=false
        appendInt32(body, 10, 0); // unknown1=0
        appendBool(body, 13, NO); // wasStream=false
        appendString(body, 14, @"ru"); // responseLang=ru
        appendInt32(body, 15, 1); // unknown2=1
        appendInt32(body, 16, 2); // unknown3=2
        appendBool(body, 17, NO); // bypassCache=false
        appendBool(body, 18, NO); // useLivelyVoice=false
        appendString(body, 19, @""); // videoTitle
        
        NSString *path = @"/video-translation/translate";
        NSString *token = [NSString stringWithFormat:@"%@:%@:%@", self.sessionUUID, path, YANDEX_COMPONENT_VERSION];
        NSData *tokenData = [token dataUsingEncoding:NSUTF8StringEncoding];
        NSString *tokenSign = [YTLYandexTranslationFetcher hmacSha256SignatureForData:tokenData];
        NSString *sign = [YTLYandexTranslationFetcher hmacSha256SignatureForData:body];
        
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@", YANDEX_API_HOST, path]]];
        req.HTTPMethod = @"POST";
        [req setValue:YANDEX_USER_AGENT forHTTPHeaderField:@"User-Agent"];
        [req setValue:@"application/x-protobuf" forHTTPHeaderField:@"Accept"];
        [req setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];
        [req setValue:sign forHTTPHeaderField:@"Vtrans-Signature"];
        [req setValue:self.sessionSecretKey forHTTPHeaderField:@"Sec-Vtrans-Sk"];
        [req setValue:[NSString stringWithFormat:@"%@:%@", tokenSign, token] forHTTPHeaderField:@"Sec-Vtrans-Token"];
        req.HTTPBody = body;
        
        [[self.urlSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error || !data) {
                if (completion) completion(nil, error ?: [NSError errorWithDomain:@"VOTError" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Networking error"}]);
                return;
            }
            
            NSUInteger offset = 0;
            NSString *url = nil;
            int32_t status = 0;
            int32_t remainingTime = 0;
            NSString *message = nil;
            
            while (offset < data.length) {
                if (offset + 1 > data.length) break; // safeguard
                uint64_t tagAndType = readVarint(data, &offset);
                int tag = tagAndType >> 3;
                int type = tagAndType & 7;
                
                if (tag == 1 && type == 2) {
                    url = readString(data, &offset);
                } else if (tag == 4 && type == 0) {
                    status = (int32_t)readVarint(data, &offset);
                } else if (tag == 5 && type == 0) {
                    remainingTime = (int32_t)readVarint(data, &offset);
                } else if (tag == 9 && type == 2) {
                    message = readString(data, &offset);
                } else {
                    if (type == 0) readVarint(data, &offset);
                    else if (type == 1) offset += 8;
                    else if (type == 2) offset += readVarint(data, &offset);
                    else if (type == 5) offset += 4;
                    else break; // unknown type, bail
                }
            }
            
            if (status == 1 && url.length > 0) {
                // SUCCESS
                if (completion) completion([NSURL URLWithString:url], nil);
            } else if (status == 2) {
                // WAITING
                if (completion) completion(nil, [NSError errorWithDomain:@"VOTError" code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Translation is processing... wait %d sec", remainingTime]}]);
            } else {
                if (completion) completion(nil, [NSError errorWithDomain:@"VOTError" code:status userInfo:@{NSLocalizedDescriptionKey: message ?: @"Failed to translate video"}]);
            }
        }] resume];
    }];
}

+ (void)requestTranslationForVideoID:(NSString *)videoID
                            duration:(NSTimeInterval)duration
                   completionHandler:(void(^)(NSURL *audioURL, NSError *error))completion {
    [[self sharedInstance] requestTranslationForVideoID:videoID duration:duration completionHandler:completion];
}

@end
