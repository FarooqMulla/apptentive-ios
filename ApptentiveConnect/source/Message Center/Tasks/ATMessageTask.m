//
//  ATMessageTask.m
//  ApptentiveConnect
//
//  Created by Andrew Wooster on 10/2/12.
//  Copyright (c) 2012 Apptentive, Inc. All rights reserved.
//

#import "ATMessageTask.h"
#import "ATBackend.h"
#import "ATData.h"
#import "ATLog.h"
#import "ATMessage.h"
#import "ATActivityFeedUpdater.h"
#import "ATWebClient.h"
#import "ATWebClient+MessageCenter.h"
#import "PJSONKit.h"

#define kATMessageTaskCodingVersion 2

@interface ATMessageTask (Private)
- (void)setup;
- (void)teardown;
- (BOOL)processResult:(NSDictionary *)jsonMessage;
@end

@implementation ATMessageTask
@synthesize pendingMessageID;

- (id)initWithCoder:(NSCoder *)coder {
	if ((self = [super init])) {
		int version = [coder decodeIntForKey:@"version"];
		if (version == kATMessageTaskCodingVersion) {
			self.pendingMessageID = [coder decodeObjectForKey:@"pendingMessageID"];
		} else {
			[self release];
			return nil;
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	[coder encodeInt:kATMessageTaskCodingVersion forKey:@"version"];
	[coder encodeObject:self.pendingMessageID forKey:@"pendingMessageID"];
}

- (void)dealloc {
	[self teardown];
	[pendingMessageID release], pendingMessageID = nil;
	[super dealloc];
}

- (BOOL)canStart {
	if ([[ATBackend sharedBackend] apiKey] == nil) {
		return NO;
	}
	if (![ATActivityFeedUpdater activityFeedExists]) {
		return NO;
	}
	return YES;
}

- (void)start {
	if (!request) {
		ATMessage *message = [[ATMessage findMessageWithPendingID:self.pendingMessageID] retain];
		if (message == nil) {
			ATLogError(@"Warning: Message was nil in message task.");
			self.finished = YES;
			return;
		}
		request = [[[ATWebClient sharedClient] requestForPostingMessage:message] retain];
		if (request != nil) {
			request.delegate = self;
			[request start];
			self.inProgress = YES;
		} else {
			self.finished = YES;
		}
	}
}

- (void)stop {
	if (request) {
		request.delegate = nil;
		[request cancel];
		[request release], request = nil;
		self.inProgress = NO;
	}
}

- (float)percentComplete {
	if (request) {
		return [request percentageComplete];
	} else {
		return 0.0f;
	}
}

- (NSString *)taskName {
	return @"message";
}

#pragma mark ATAPIRequestDelegate
- (void)at_APIRequestDidFinish:(ATAPIRequest *)sender result:(NSObject *)result {
	@synchronized(self) {
		[self retain];
		
		if ([result isKindOfClass:[NSDictionary class]] && [self processResult:(NSDictionary *)result]) {
			self.finished = YES;
		} else {
			ATLogError(@"Message result is not NSDictionary!");
			self.failed = YES;
		}
		[self stop];
		[self release];
	}
}

- (void)at_APIRequestDidProgress:(ATAPIRequest *)sender {
	// pass
}

- (void)at_APIRequestDidFail:(ATAPIRequest *)sender {
	@synchronized(self) {
		[self retain];
		self.lastErrorTitle = sender.errorTitle;
		self.lastErrorMessage = sender.errorMessage;
		
		ATMessage *message = [[ATMessage findMessageWithPendingID:self.pendingMessageID] retain];
		if (message == nil) {
			ATLogError(@"Warning: Message went away during task.");
			self.finished = YES;
			return;
		}
		[message setErrorOccurred:@(YES)];
		if (sender.errorResponse != nil) {
			NSObject *errorObject = [sender.errorResponse ATobjectFromJSONString];
			if (errorObject != nil && [errorObject isKindOfClass:[NSDictionary class]]) {
				NSDictionary *errorDictionary = (NSDictionary *)errorObject;
				if ([errorDictionary objectForKey:@"errors"]) {
					ATLogInfo(@"ATAPIRequest server error: %@", [errorDictionary objectForKey:@"errors"]);
					[message setErrorMessageJSON:sender.errorResponse];
				}
			}
			[message setPendingState:@(ATPendingMessageStateError)];
		}
		NSError *error = nil;
		NSManagedObjectContext *context = [[ATBackend sharedBackend] managedObjectContext];
		if (![context save:&error]) {
			ATLogError(@"Failed to save message after API failure: %@", error);
		}
		ATLogInfo(@"ATAPIRequest failed: %@, %@", sender.errorTitle, sender.errorMessage);
		if (self.failureCount > 2) {
			self.finished = YES;
		} else {
			self.failed = YES;
		}
		[self stop];
		[self release];
	}
}
@end

@implementation ATMessageTask (Private)
- (void)setup {
	
}

- (void)teardown {
	[self stop];
}

- (BOOL)processResult:(NSDictionary *)jsonMessage {
	ATLogInfo(@"getting json result: %@", jsonMessage);
	NSManagedObjectContext *context = [[ATBackend sharedBackend] managedObjectContext];
	
	ATMessage *message = [[ATMessage findMessageWithPendingID:self.pendingMessageID] retain];
	if (message == nil) {
		ATLogError(@"Warning: Message went away during task.");
		return YES;
	}
	[message updateWithJSON:jsonMessage];
	message.pendingState = [NSNumber numberWithInt:ATPendingMessageStateConfirmed];
	
	NSError *error = nil;
	if (![context save:&error]) {
		ATLogError(@"Failed to save new message: %@", error);
		return NO;
	}
	return YES;
}
@end
