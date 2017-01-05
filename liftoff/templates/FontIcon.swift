//
//  FontIcon
//

import UIKit

enum Icon: String {
	case Back = "\u{e903}"
    case Close = "\u{e904}"
    case Next = "\u{e905}"
    case Question = "\u{e906}"
    case Tick = "\u{e907}"
    case History = "\u{e900}"
    case New = "\u{e901}"
    case Recents = "\u{e902}"
}

class FontIcon {

	var code: String
	var fontName = "icomoon"
	var pointSize: CGFloat = 10
	var color: UIColor = UIColor.black

	init(code: Icon) {
		self.code = code.rawValue
	}

    func attributes() -> [String:AnyObject] {
        return [
            NSFontAttributeName: UIFont(name: self.fontName, size: self.pointSize)!,
            NSForegroundColorAttributeName: self.color
        ]
    }

	func attributedString() -> NSAttributedString {
		return NSAttributedString(string: self.code, attributes: self.attributes())
	}

	func mutableAttributedString() -> NSMutableAttributedString {
		return self.attributedString().mutableCopy() as! NSMutableAttributedString
	}

	func image(color: UIColor?, size: CGSize) -> UIImage {

        if let col = color {
            self.color = col
        }

        self.pointSize = size.height

		UIGraphicsBeginImageContextWithOptions(size, false, 0)
        self.code.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height), withAttributes: self.attributes())
		let image: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
		UIGraphicsEndImageContext()
		return image.withRenderingMode(.alwaysOriginal)
	}
}
