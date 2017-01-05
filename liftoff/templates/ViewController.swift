//
//  ViewController.swift
//
//

import UIKit
import SVProgressHUD

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        SVProgressHUD.showSuccess(withStatus: "You can now create Localizable.strings")
    }

}
