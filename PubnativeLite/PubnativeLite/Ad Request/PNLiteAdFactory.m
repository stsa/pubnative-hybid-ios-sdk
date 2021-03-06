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

#import "PNLiteAdFactory.h"
#import "HyBidRequestParameter.h"
#import "HyBidSettings.h"
#import "PNLiteCryptoUtils.h"
#import "PNLiteMeta.h"
#import "PNLiteAsset.h"
#import "HyBidConstants.h"

@implementation PNLiteAdFactory

- (PNLiteAdRequestModel *)createAdRequestWithZoneID:(NSString *)zoneID
                                      andWithAdSize:(NSString *)adSize
                             andWithIntegrationType:(IntegrationType)integrationType {
    PNLiteAdRequestModel *adRequestModel = [[PNLiteAdRequestModel alloc] init];
    adRequestModel.requestParameters[HyBidRequestParameter.zoneId] = zoneID;
    adRequestModel.requestParameters[HyBidRequestParameter.appToken] = [HyBidSettings sharedInstance].appToken;
    adRequestModel.requestParameters[HyBidRequestParameter.os] = [HyBidSettings sharedInstance].os;
    adRequestModel.requestParameters[HyBidRequestParameter.osVersion] = [HyBidSettings sharedInstance].osVersion;
    adRequestModel.requestParameters[HyBidRequestParameter.deviceModel] = [HyBidSettings sharedInstance].deviceName;
    adRequestModel.requestParameters[HyBidRequestParameter.coppa] = [HyBidSettings sharedInstance].coppa ? @"1" : @"0";
    [self setIDFA:adRequestModel];
    adRequestModel.requestParameters[HyBidRequestParameter.locale] = [HyBidSettings sharedInstance].locale;
    if (![HyBidSettings sharedInstance].coppa) {
        adRequestModel.requestParameters[HyBidRequestParameter.age] = [[HyBidSettings sharedInstance].targeting.age stringValue];
        adRequestModel.requestParameters[HyBidRequestParameter.gender] = [HyBidSettings sharedInstance].targeting.gender;
        adRequestModel.requestParameters[HyBidRequestParameter.keywords] = [[HyBidSettings sharedInstance].targeting.interests componentsJoinedByString:@","];
    }
    adRequestModel.requestParameters[HyBidRequestParameter.test] =[HyBidSettings sharedInstance].test ? @"1" : @"0";
    if (adSize) {
        adRequestModel.requestParameters[HyBidRequestParameter.assetLayout] = adSize;
    } else {
        [self setDefaultAssetFields:adRequestModel];
    }
    [self setDefaultMetaFields:adRequestModel];
    [self setDisplayManager:adRequestModel withIntegrationType:integrationType];
    return adRequestModel;
}

- (void)setDisplayManager:(PNLiteAdRequestModel *)adRequestModel withIntegrationType:(IntegrationType)integrationType {
    adRequestModel.requestParameters[HyBidRequestParameter.displayManager] = HYBID_SDK_NAME;
    adRequestModel.requestParameters[HyBidRequestParameter.displayManagerVersion] = [NSString stringWithFormat:@"%@_%@_%@", @"sdkios", [HyBidIntegrationType getIntegrationTypeCodeFromIntegrationType:integrationType] ,HYBID_SDK_VERSION];
}

- (void)setIDFA:(PNLiteAdRequestModel *)adRequestModel {
    NSString *advertisingId = [HyBidSettings sharedInstance].advertisingId;
    if (!advertisingId || advertisingId.length == 0) {
        adRequestModel.requestParameters[HyBidRequestParameter.dnt] = @"1";
    } else {
        adRequestModel.requestParameters[HyBidRequestParameter.idfa] = advertisingId;
        adRequestModel.requestParameters[HyBidRequestParameter.idfamd5] = [PNLiteCryptoUtils md5WithString:advertisingId];
        adRequestModel.requestParameters[HyBidRequestParameter.idfasha1] = [PNLiteCryptoUtils sha1WithString:advertisingId];
    }
}

- (void)setDefaultAssetFields:(PNLiteAdRequestModel *)adRequestModel {
    if (!adRequestModel.requestParameters[HyBidRequestParameter.assetsField]
        && !adRequestModel.requestParameters[HyBidRequestParameter.assetLayout]) {
        
        NSArray *assets = @[PNLiteAsset.title,
                            PNLiteAsset.body,
                            PNLiteAsset.icon,
                            PNLiteAsset.banner,
                            PNLiteAsset.callToAction,
                            PNLiteAsset.rating];
        
        adRequestModel.requestParameters[HyBidRequestParameter.assetsField] = [assets componentsJoinedByString:@","];
    }
}

- (void)setDefaultMetaFields:(PNLiteAdRequestModel *)adRequestModel {
    NSString *metaFieldsString = adRequestModel.requestParameters[HyBidRequestParameter.metaField];
    NSMutableArray *newMetaFields = [NSMutableArray array];
    if (metaFieldsString && metaFieldsString.length > 0) {
        newMetaFields = [[metaFieldsString componentsSeparatedByString:@","] mutableCopy];
    }
    if (![newMetaFields containsObject:PNLiteMeta.revenueModel]) {
        [newMetaFields addObject:PNLiteMeta.revenueModel];
    }
    if (![newMetaFields containsObject:PNLiteMeta.contentInfo]) {
        [newMetaFields addObject:PNLiteMeta.contentInfo];
    }
    if (![newMetaFields containsObject:PNLiteMeta.points]) {
        [newMetaFields addObject:PNLiteMeta.points];
    }
    if (![newMetaFields containsObject:PNLiteMeta.creativeId]) {
        [newMetaFields addObject:PNLiteMeta.creativeId];
    }
    adRequestModel.requestParameters[HyBidRequestParameter.metaField] = [newMetaFields componentsJoinedByString:@","];
}

@end
