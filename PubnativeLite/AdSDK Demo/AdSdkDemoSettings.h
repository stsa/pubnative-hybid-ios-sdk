//
//  AdSdkDemoSettings.h
//  AdSDK Demo
//
//  Created by Eros Garcia Ponte on 25.03.20.
//  Copyright © 2020 Can Soykarafakili. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <HyBid/HyBid.h>

@interface AdSdkDemoSettings : NSObject

@property (nonatomic, strong) NSString *appToken;
@property (nonatomic, strong) NSString *partnerKeyword;

+ (AdSdkDemoSettings *)sharedInstance;

@end