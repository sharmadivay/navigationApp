//
//  SearchLocationTableViewCell.swift
//  Travel
//
//  Created by Divay Sharma on 19/08/25.
//

import UIKit

class SearchLocationTableViewCell: UITableViewCell {

    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var locationTitle: UILabel!
    @IBOutlet weak var locationAddress: UILabel!
    
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

    }

}
