//
//  Copyright © 2018 PubNative. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "PNLiteMetaData.h"
#import "PNLiteSerialization.h"
#import "PNLiteCrashLogger.h"

@interface PNLiteMetaData ()
@property(atomic, strong) NSMutableDictionary *dictionary;
@end

@implementation PNLiteMetaData

- (id)init {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    return [self initWithDictionary:dict];
}

- (id)initWithDictionary:(NSMutableDictionary *)dict {
    if (self = [super init]) {
        self.dictionary = dict;
    }
    [self.delegate metaDataChanged:self];
    return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    @synchronized(self) {
        NSMutableDictionary *dict = [self.dictionary mutableCopy];
        return [[PNLiteMetaData alloc] initWithDictionary:dict];
    }
}

- (NSMutableDictionary *)getTab:(NSString *)tabName {
    @synchronized(self) {
        NSMutableDictionary *tab = self.dictionary[tabName];
        if (!tab) {
            tab = [NSMutableDictionary dictionary];
            self.dictionary[tabName] = tab;
        }
        return tab;
    }
}

- (void)clearTab:(NSString *)tabName {
    @synchronized(self) {
        [self.dictionary removeObjectForKey:tabName];
    }

    [self.delegate metaDataChanged:self];
}

- (NSDictionary *)toDictionary {
    @synchronized(self) {
        return [NSDictionary dictionaryWithDictionary:self.dictionary];
    }
}

- (void)addAttribute:(NSString *)attributeName
           withValue:(id)value
       toTabWithName:(NSString *)tabName {
    @synchronized(self) {
        if (value) {
            id cleanedValue = PNLiteSanitizeObject(value);
            if (cleanedValue) {
                [self getTab:tabName][attributeName] = cleanedValue;
            } else {
                Class klass = [value class];
                pnlite_log_err(@"Failed to add metadata: Value of class %@ is not "
                            @"JSON serializable",
                            klass);
            }
        } else {
            [[self getTab:tabName] removeObjectForKey:attributeName];
        }
    }
    [self.delegate metaDataChanged:self];
}

@end
