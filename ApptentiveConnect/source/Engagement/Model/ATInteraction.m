//
//  ATInteraction.m
//  ApptentiveConnect
//
//  Created by Peter Kamb on 8/23/13.
//  Copyright (c) 2013 Apptentive, Inc. All rights reserved.
//

#import "ATInteraction.h"
#import "ATEngagementBackend.h"
#import "ATInteractionUsageData.h"

@implementation ATInteraction

+ (ATInteraction *)interactionWithJSONDictionary:(NSDictionary *)jsonDictionary {
	ATInteraction *interaction = [[ATInteraction alloc] init];
	interaction.identifier = [jsonDictionary objectForKey:@"id"];
	interaction.priority = [[jsonDictionary objectForKey:@"priority"] intValue];
	interaction.type = [jsonDictionary objectForKey:@"type"];
	interaction.configuration = [jsonDictionary objectForKey:@"configuration"];
	interaction.criteria = [jsonDictionary objectForKey:@"criteria"];
	interaction.version = [jsonDictionary objectForKey:@"version"];
	return [interaction autorelease];
}

- (NSString *)description {	
	NSDictionary *description = @{@"identifier" : self.identifier ?: [NSNull null],
								  @"priority" : [NSNumber numberWithInt:self.priority] ?: [NSNull null],
								  @"type" : self.type ?: [NSNull null],
								  @"configuration" : self.configuration ?: [NSNull null],
								  @"criteria" : self.criteria ?: [NSNull null],
								  @"version" : self.version ?: [NSNull null]};
	
	return [description description];
}

- (id)initWithCoder:(NSCoder *)coder {
	if ((self = [super init])) {
		self.identifier = [coder decodeObjectForKey:@"identifier"];
		self.priority = [coder decodeIntForKey:@"priority"];
		self.type = [coder decodeObjectForKey:@"type"];
		self.configuration = [coder decodeObjectForKey:@"configuration"];
		self.criteria = [coder decodeObjectForKey:@"criteria"];
		self.version = [coder decodeObjectForKey:@"version"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	[coder encodeObject:self.identifier forKey:@"identifier"];
	[coder encodeInt:self.priority forKey:@"priority"];
	[coder encodeObject:self.type forKey:@"type"];
	[coder encodeObject:self.configuration forKey:@"configuration"];
	[coder encodeObject:self.criteria forKey:@"criteria"];
	[coder encodeObject:self.version forKey:@"version"];
}

- (ATInteractionUsageData *)usageData {
	return [ATInteractionUsageData usageDataForInteraction:self];
}

- (BOOL)criteriaAreMet {
	return [self criteriaAreMetForUsageData:[self usageData]];
}

- (BOOL)criteriaAreMetForUsageData:(ATInteractionUsageData *)usageData {
	BOOL criteriaAreMet = NO;
	NSPredicate *predicate = [self criteriaPredicate];
	if (predicate) {
		criteriaAreMet = [predicate evaluateWithObject:[usageData predicateEvaluationDictionary]];
		if (!criteriaAreMet) {
			ATLogInfo(@"Interaction predicate failed evaluation.");
			ATLogInfo(@"Predicate: %@", predicate);
			ATLogInfo(@"Interaction usage data: %@", [usageData predicateEvaluationDictionary]);
		}
	} else {
		ATLogError(@"Interaction predicate not correct");
	}
	
	return criteriaAreMet;
}

- (NSPredicate *)criteriaPredicate {
	BOOL error = NO;
	NSPredicate *criteriaPredicate = [ATInteraction predicateForInteractionCriteria:self.criteria hasError:&error];
	if (!criteriaPredicate || error) {
		return nil;
	}
	
	return criteriaPredicate;
}

+ (NSPredicate *)predicateForInteractionCriteria:(NSDictionary *)interactionCriteria hasError:(BOOL *)hasError {
	NSMutableArray *parts = [NSMutableArray array];
	NSCompoundPredicateType predicateType = NSAndPredicateType;
	
	for (NSString *key in interactionCriteria) {
		NSObject *object = [interactionCriteria objectForKey:key];
		
		if ([object isKindOfClass:[NSArray class]]) {
			if ([key isEqualToString:@"$and"]) {
				predicateType = NSAndPredicateType;
			} else if ([key isEqualToString:@"$or"]) {
				predicateType = NSOrPredicateType;
			} else {
				*hasError = YES;
			}
			
			NSMutableArray *criteria = [NSMutableArray array];
			for (NSDictionary *dictionary in (NSArray *)object) {
				NSPredicate *criterion = [self predicateForInteractionCriteria:dictionary hasError:hasError];
				[criteria addObject:criterion];
			}
			[parts addObjectsFromArray:criteria];
		}
		else {
			// Implicit "==" if object is a string/number
			NSDictionary *equalityDictionary = ([object isKindOfClass:[NSDictionary class]]) ? (NSDictionary *)object : @{@"==" : object};
			
			NSMutableArray *criteria = [NSMutableArray array];
			for (NSString *equalityKey in equalityDictionary) {
				NSString *equalitySymbol = nil;
				if ([equalityKey isEqualToString:@"=="]) {
					equalitySymbol = @"==";
				}
				else if ([equalityKey isEqualToString:@"$gt"]) {
					equalitySymbol = @">";
				}
				else if ([equalityKey isEqualToString:@"$gte"]) {
					equalitySymbol = @">=";
				}
				else if ([equalityKey isEqualToString:@"$lt"]) {
					equalitySymbol = @"<";
				}
				else if ([equalityKey isEqualToString:@"$lte"]) {
					equalitySymbol = @"<=";
				}
				else if ([equalityKey isEqualToString:@"$ne"]) {
					equalitySymbol = @"!=";
				}
				else {
					*hasError = YES;
				}
			
				NSObject *value = [equalityDictionary objectForKey:equalityKey];
				NSString *placeholder = [[@"(%K " stringByAppendingString:equalitySymbol] stringByAppendingString:@" %@)"];
				NSPredicate *criterion = [NSCompoundPredicate predicateWithFormat:placeholder argumentArray:@[key, value]];
				[criteria addObject:criterion];
			}
			
			[parts addObjectsFromArray:criteria];
		}
	}
	
	NSPredicate *result = [[[NSCompoundPredicate alloc] initWithType:predicateType subpredicates:parts] autorelease];
	return result;
}

@end
