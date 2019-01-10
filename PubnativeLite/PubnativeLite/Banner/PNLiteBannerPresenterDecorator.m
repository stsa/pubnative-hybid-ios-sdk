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

#import "PNLiteBannerPresenterDecorator.h"

@interface PNLiteBannerPresenterDecorator ()

@property (nonatomic, strong) HyBidAdPresenter *bannerPresenter;
@property (nonatomic, strong) HyBidAdTracker *adTracker;
@property (nonatomic, strong) NSObject<HyBidBannerPresenterDelegate> *bannerPresenterDelegate;

@end

@implementation PNLiteBannerPresenterDecorator

- (void)dealloc
{
    self.bannerPresenter = nil;
    self.adTracker = nil;
    self.bannerPresenterDelegate = nil;
}

- (void)load
{
    [self.bannerPresenter load];
}

- (void)startTracking
{
    [self.bannerPresenter startTracking];
}

- (void)stopTracking
{
    [self.bannerPresenter stopTracking];
}

- (instancetype)initWithBannerPresenter:(HyBidAdPresenter *)bannerPresenter
                          withAdTracker:(HyBidAdTracker *)adTracker
                           withDelegate:(NSObject<HyBidBannerPresenterDelegate> *)delegate
{
    self = [super init];
    if (self) {
        self.bannerPresenter = bannerPresenter;
        self.adTracker = adTracker;
        self.bannerPresenterDelegate = delegate;
    }
    return self;
}

#pragma mark HyBidBannerPresenterDelegate

- (void)bannerPresenter:(HyBidAdPresenter *)bannerPresenter didLoadWithBanner:(UIView *)banner
{
    [self.adTracker trackImpression];
    [self.bannerPresenterDelegate bannerPresenter:bannerPresenter didLoadWithBanner:banner];
}

- (void)bannerPresenterDidClick:(HyBidAdPresenter *)bannerPresenter
{
    [self.adTracker trackClick];
    [self.bannerPresenterDelegate bannerPresenterDidClick:bannerPresenter];
}

- (void)bannerPresenter:(HyBidAdPresenter *)bannerPresenter didFailWithError:(NSError *)error
{
    [self.bannerPresenterDelegate bannerPresenter:bannerPresenter didFailWithError:error];
}

@end
