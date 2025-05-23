#import <stdio.h>

#import <Foundation/Foundation.h>
#import <rocketbootstrap/rocketbootstrap.h>

#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"


static id RocketGetJSONResponse(NSString *urlString, NSString *syncType)
{
    CFMessagePortRef remotePort = rocketbootstrap_cfmessageportcreateremote(NULL, CFSTR("com.darwindev.kbsync.port"));
    if (!remotePort) {
		fprintf(stderr, "no remote port found\n");
		return [NSDictionary dictionary];
	}

    CFDataRef data = (CFDataRef)CFBridgingRetain([NSPropertyListSerialization dataWithPropertyList:@{
        @"url": urlString, @"kbsyncType": syncType, @"sbsyncType": syncType} format:NSPropertyListBinaryFormat_v1_0 options:kNilOptions error:nil]);
    CFDataRef returnData = NULL;
    SInt32 status =
        CFMessagePortSendRequest(
            remotePort,
            0x1111,
            data,
            3.0,
            3.0,
            kCFRunLoopDefaultMode,
            &returnData
        );

    CFRelease(data);

    if (status != kCFMessagePortSuccess) {
		fprintf(stderr, "CFMessagePortSendRequest %d\n", status);

        CFMessagePortInvalidate(remotePort);
        CFRelease(remotePort);
		return [NSDictionary dictionary];
    }

    CFMessagePortInvalidate(remotePort);
    CFRelease(remotePort);

    return [NSPropertyListSerialization propertyListWithData:CFBridgingRelease(returnData) options:kNilOptions format:nil error:nil];
}

static id RocketGetJSONResponse2(NSData *signBody, NSNumber *mescalType, NSDictionary *bag)
{
    CFMessagePortRef remotePort = rocketbootstrap_cfmessageportcreateremote(NULL, CFSTR("com.darwindev.kbsync.port"));
    if (!remotePort) {
		fprintf(stderr, "no remote port found\n");
		return [NSDictionary dictionary];
	}

    CFDataRef data = (CFDataRef)CFBridgingRetain([NSPropertyListSerialization dataWithPropertyList:@{
        @"body": signBody, @"mescalType": mescalType, @"bag": bag} format:NSPropertyListBinaryFormat_v1_0 options:kNilOptions error:nil]);
    CFDataRef returnData = NULL;
    SInt32 status =
        CFMessagePortSendRequest(
            remotePort,
            0x2222,
            data,
            3.0,
            3.0,
            kCFRunLoopDefaultMode,
            &returnData
        );

    CFRelease(data);

    if (status != kCFMessagePortSuccess) {
		fprintf(stderr, "CFMessagePortSendRequest %d\n", status);

        CFMessagePortInvalidate(remotePort);
        CFRelease(remotePort);
		return [NSDictionary dictionary];
    }

    CFMessagePortInvalidate(remotePort);
    CFRelease(remotePort);

    return [NSPropertyListSerialization propertyListWithData:CFBridgingRelease(returnData) options:kNilOptions format:nil error:nil];
}


int main(int argc, char *argv[], char *envp[]) {

    if (argc != 2 && argc != 3) {
        fprintf(stderr, "usage: %s [url] [-p port]\n", argv[0]);
        return 1;
    }

    if (argc == 2) {

        // one-time execute

        NSString *urlString = [NSString stringWithUTF8String:argv[1]];
        id returnObj = RocketGetJSONResponse(urlString, @"base64");
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:returnObj options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:nil];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        if (jsonString) {
            printf("%s\n", [jsonString UTF8String]);
        }

        return jsonString != nil ? 0 : 1;
    } else {

        // launch server

        NSInteger port = [[NSString stringWithUTF8String:argv[2]] integerValue];
        if (port <= 0 || port > 65535) {
            fprintf(stderr, "invalid server port\n");
            return 1;
        }

        GCDWebServer *webServer = [[GCDWebServer alloc] init];
        GCDWebServerAsyncProcessBlock webCallback = ^(GCDWebServerRequest *request, GCDWebServerCompletionBlock completionBlock) {

            id returnObj = nil;
            if ([[[request URL] path] isEqualToString:@"/sign"]) {
                NSString *bodyString = [request query][@"body"];
                NSData *body = [[NSData alloc] initWithBase64EncodedString:bodyString options:0];

                NSString *mescalTypeString = [request query][@"mescalType"];
                int mescalType = [mescalTypeString intValue];

                NSString *bagJsonString = [request query][@"bagJson"];
                NSData *bagJsonData = [bagJsonString dataUsingEncoding:NSUTF8StringEncoding];
                NSError *error = nil;
                NSDictionary *bagJson = [NSJSONSerialization JSONObjectWithData:bagJsonData options:0 error:&error];
                if (error != nil) {
                    completionBlock([GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"invalid bag json"]);
                    return;
                }

                returnObj = RocketGetJSONResponse2(body, @(mescalType), bagJson);
                if (!returnObj) {
                    completionBlock([GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError message:@"server error"]);
                    return;
                }
            } else {
                NSString *urlString = [request query][@"url"];
                if (!urlString) {
                    completionBlock([GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"invalid url"]);
                    return;
                }

                returnObj = RocketGetJSONResponse(urlString, @"hex");
                if (!returnObj) {
                    completionBlock([GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError message:@"failed capture data"]);
                    return;
                }
            }


            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:returnObj options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:nil];
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

            if (jsonString) {
                NSLog(@"%@", jsonString);
            }

            completionBlock([GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"]);
        };

        [webServer addDefaultHandlerForMethod:@"GET"
                                 requestClass:[GCDWebServerRequest class]
                            asyncProcessBlock:webCallback];
        [webServer addDefaultHandlerForMethod:@"POST"
                                 requestClass:[GCDWebServerRequest class]
                            asyncProcessBlock:webCallback];

        [webServer startWithPort:port bonjourName:nil];
        NSLog(@"Using -s %@ with NyaMisty/ipatool-py...", webServer.serverURL);

        CFRunLoopRun();
        return 0;
    }
}
