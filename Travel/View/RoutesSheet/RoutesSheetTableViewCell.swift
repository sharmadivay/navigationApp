//
//  RoutesSheetTableViewCell.swift
//  Travel
//
//  Created by Divay Sharma on 20/08/25.
//

import UIKit
import ComposableArchitecture
import MapKit

class RoutesSheetTableViewCell: UITableViewCell {

    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var goButton: UIButton!
    
    var viewStore: ViewStoreOf<MainFeature>?
    var route: MKRoute? = nil
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

    }
    
    @IBAction func goButtonTapped(_ sender: Any) {
        guard let viewStore = self.viewStore else { return }
        viewStore.send(.setGoButtonTapped(route))
    }
    
}
