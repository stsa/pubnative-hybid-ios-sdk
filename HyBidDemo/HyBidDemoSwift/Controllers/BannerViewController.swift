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

import UIKit
import HyBid
import CoreLocation

class BannerViewController: UIViewController {

    @IBOutlet weak var bannerAdView: VWAdvertView!
    
    var locationManager = CLLocationManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.requestLocation()
    }
    
    @IBAction func loadAdButtonClicked(_ sender: Any) {
        requestAd()
    }
    
    func requestAd() {
        bannerAdView.delegate = self
        bannerAdView.adSize = kVWAdSizeBanner
        let adRequest = VWAdRequest(contentCategoryID: .artsAndEntertainment)
        bannerAdView.loadRequest(withZoneID: "2", andWith: adRequest)
    }
    
    func requestLocation() {
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        locationManager.requestWhenInUseAuthorization()
    }
    
    func showAlertControllerWithMessage(for error: String) {
        let alertController = UIAlertController(title: "I have a bad feeling about this... 🙄", message: error, preferredStyle: .alert)
        let dismissAction = UIAlertAction(title: "Dismiss", style: .cancel, handler: nil)
        let retryAction = UIAlertAction(title: "Retry", style: .default) { (_) in
            self.requestAd()
        }
        alertController.addAction(dismissAction)
        alertController.addAction(retryAction)
        self.present(alertController, animated: true, completion: nil)
    }
    
}

extension BannerViewController: VWAdvertViewDelegate {
    
    func advertViewDidReceiveAd(_ adView: VWAdvertView) {
        print("Banner Ad View did load:")
    }
    
    func advertView(_ adView: VWAdvertView, didFailToReceiveAdWithError error: Error?) {
        guard let `error` = error else {return}
        print("Banner Ad View did fail with error: ", error.localizedDescription)
        showAlertControllerWithMessage(for: error.localizedDescription)
    }
    
}
