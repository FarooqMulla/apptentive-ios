//
//  PSWebClient.m
//  AmidstApp
//
//  Created by Andrew Wooster on 7/28/09.
//  Copyright 2009 Planetary Scale LLC. All rights reserved.
//

#import "ATWebClient.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif
#import "ATConnectionManager.h"
#import "ATURLConnection.h"
#import "ATUtilities.h"

#ifdef SUPPORT_JSON
#import "JSON.h"
#endif

#define kCommonChannelName (@"ATWebClient")
#define kUserAgent (@"ApptentiveConnect/1.0 (iOS)")

@implementation ATWebClient
@synthesize returnType;
@synthesize failed;
@synthesize errorTitle;
@synthesize errorMessage;
@synthesize channelName;
@synthesize timeoutInterval;

- (id)initWithTarget:(id)aDelegate action:(SEL)anAction {
	if ((self = [super init])) {
		returnType = ATWebClientReturnTypeString;
		delegate = aDelegate;
		action = anAction;
		channelName = kCommonChannelName;
		timeoutInterval = 30.0;
	}
	return self;
}

- (void)showAlert {
	if (self.failed) {
#if TARGET_OS_IPHONE
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:self.errorTitle message:self.errorMessage delegate:self cancelButtonTitle:NSLocalizedString(@"Close", nil) otherButtonTitles:nil];
		[alert show];
		[alert release];
#endif
	}
}

- (void)cancel {
	@synchronized(self) {
		cancelled = YES;
	}
}

- (NSString *)stringForParameters:(NSDictionary *)parameters {
	NSMutableString *result = [[NSMutableString alloc] init];
	do { // once
		if (!parameters || [parameters count] == 0) {
			[result appendString:@""];
			break;
		}
		
		BOOL appendAmpersand = NO;
		for (NSString *key in [parameters keyEnumerator]) {
			NSString *val = [self stringForParameter:[parameters objectForKey:key]];
			if (!val) continue;
			
			if (appendAmpersand) {
				[result appendString:@"&"];
			}
            [result appendString:[ATUtilities stringByEscapingForURLArguments:key]];
			[result appendString:@"="];
            [result appendString:[ATUtilities stringByEscapingForURLArguments:val]];
			appendAmpersand = YES;
		}
	} while (NO);
	return [result autorelease];
}

- (NSString *)stringForParameter:(id)value {
	NSString *result = nil;
	if ([value isKindOfClass:[NSString class]]) {
		result = (NSString *)value;
	} else if ([value isKindOfClass:[NSNumber class]]) {
		result = [(NSNumber *)value stringValue];
	}
	return result;
}

#pragma mark ATURLConnection Delegates
- (void)connectionFinishedSuccessfully:(ATURLConnection *)sender {
	@synchronized(self) {
		if (cancelled) return;
	}
	int statusCode = sender.statusCode;
	BOOL readData = NO;
	switch (statusCode) {
		case 200:
		case 400: // rate limit reached
		case 403: // whatevs, probably private feed
			readData = YES;
			break;
		case 401:
			self.failed = YES;
			self.errorTitle = NSLocalizedString(@"Authentication Failed", @"");
			self.errorMessage = NSLocalizedString(@"Wrong username and/or password.", @"");
			break;
		case 304:
			break;
		default:
			self.failed = YES;
			self.errorTitle = NSLocalizedString(@"Server error.", @"");
			self.errorMessage = [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
			break;
	}
	
	id result = nil;
	do { // once
		//if (!readData) break;
		
		NSData *d = [sender responseData];
		if (!d) break;
		if (self.returnType == ATWebClientReturnTypeData) {
			result = d;
			break;
		}
		
		NSString *s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
		if (!s) break;
		if (self.returnType == ATWebClientReturnTypeString) {
			result = s;
			break;
		}
        
#ifdef SUPPORT_JSON
		if (self.returnType == ATWebClientReturnTypeJSON) {
			id json = [s JSONValue];
			if (!json) {
				self.failed = YES;
				self.errorTitle = NSLocalizedString(@"Invalid response from server.", @"");
				self.errorMessage = NSLocalizedString(@"Server did not return properly formatted JSON.", @"");
			}
			result = json;
			break;
		}
#endif
	} while (NO);
	
	if (delegate && action) {
		[delegate performSelector:action withObject:self withObject:result];
	}
}

- (void)connectionFailed:(ATURLConnection *)sender {
	@synchronized(self) {
		if (cancelled) return;
	}
	self.failed = YES;
	if (sender.failedAuthentication || sender.statusCode == 401) {
		self.errorTitle = NSLocalizedString(@"Authentication Failed", @"");
		self.errorMessage = NSLocalizedString(@"Wrong username and/or password.", @"");
	} else {
		self.errorTitle = NSLocalizedString(@"Network Connection Error", @"");
		self.errorMessage = [sender.connectionError localizedDescription];
	}
	if (delegate && action) {
		[delegate performSelector:action withObject:self withObject:nil];
	}
}

#pragma mark Private Methods
- (void)get:(NSURL *)theURL {
	ATConnectionManager *cm = [ATConnectionManager sharedSingleton];
	ATURLConnection *conn = [[ATURLConnection alloc] initWithURL:theURL delegate:self];
	conn.timeoutInterval = self.timeoutInterval;
	[self addAPIHeaders:conn];
	[cm addConnection:conn toChannel:self.channelName];
	[conn release];
	[cm start];
}

- (void)post:(NSURL *)theURL {
	ATConnectionManager *cm = [ATConnectionManager sharedSingleton];
	ATURLConnection *conn = [[ATURLConnection alloc] initWithURL:theURL delegate:self];
	conn.timeoutInterval = self.timeoutInterval;
	[self addAPIHeaders:conn];
	[conn setHTTPMethod:@"POST"];
	
	[cm addConnection:conn toChannel:self.channelName];
	[conn release];
	[cm start];
}

- (void)post:(NSURL *)theURL JSON:(NSString *)body {
	ATConnectionManager *cm = [ATConnectionManager sharedSingleton];
	ATURLConnection *conn = [[ATURLConnection alloc] initWithURL:theURL delegate:self];
	conn.timeoutInterval = self.timeoutInterval;
	[self addAPIHeaders:conn];
	[conn setHTTPMethod:@"POST"];
	[conn setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
	int length = [body lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	[conn setValue:[NSString stringWithFormat:@"%d", length] forHTTPHeaderField:@"Content-Length"];
	[conn setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
	
	[cm addConnection:conn toChannel:self.channelName];
	[conn release];
	[cm start];
}

- (void)post:(NSURL *)theURL body:(NSString *)body {
	ATConnectionManager *cm = [ATConnectionManager sharedSingleton];
	ATURLConnection *conn = [[ATURLConnection alloc] initWithURL:theURL delegate:self];
	conn.timeoutInterval = self.timeoutInterval;
	[self addAPIHeaders:conn];
	[conn setHTTPMethod:@"POST"];
	[conn setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	int length = [body lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	[conn setValue:[NSString stringWithFormat:@"%d", length] forHTTPHeaderField:@"Content-Length"];
	[conn setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
	
	[cm addConnection:conn toChannel:self.channelName];
	[conn release];
	[cm start];
}


- (void)addAPIHeaders:(ATURLConnection *)conn {
	[conn setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];
	[conn setValue: @"gzip" forHTTPHeaderField: @"Accept-Encoding"];
}

#pragma mark Memory Management
- (void)dealloc {
    delegate = nil;
	[errorTitle release];
	[errorMessage release];
	[channelName release];
	[super dealloc];
}
@end