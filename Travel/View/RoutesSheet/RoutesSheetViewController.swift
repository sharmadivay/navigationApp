//
//  RoutesSheetViewController.swift
//  Travel
//
//  Created by Divay Sharma on 20/08/25.
//

import UIKit
import MapKit
import ComposableArchitecture
import Combine

class RoutesSheetViewController: UIViewController {
    
    @IBOutlet weak var destinationTitle: UILabel!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var addressLabel: UILabel!
    @IBOutlet weak var segment: UISegmentedControl!
    @IBOutlet weak var routesSheetTableCiew: UITableView!
    
    var viewStore: ViewStoreOf<MainFeature>?
    var destination: MKMapItem? = nil
    var routes: [MKRoute] = []
    
    var cancelables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let destination = self.destination else { return }
        guard let viewStore = self.viewStore else { return }
        self.destinationTitle.text = destination.placemark.name
        self.addressLabel.text = destination.placemark.title
        segment.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        setupTableView()
        
        viewStore
            .publisher
            .routes
            .sink {[weak self ] routes in
                guard let self = self else { return }
                self.routes = routes
                self.routesSheetTableCiew.reloadData()
            }
            .store(in: &cancelables)
        
        if let sheet = self.sheetPresentationController {
              sheet.delegate = self
          }
    }
    
    func configure(destination: MKMapItem ) {
        self.destination = destination
    }
    
    private func setupTableView() {
        routesSheetTableCiew.delegate = self
        routesSheetTableCiew.dataSource = self
    }
    
    @IBAction func cancelButtonTapped(_ sender: Any) {
        guard let viewStore = self.viewStore else { return }
        viewStore.send(.setSheetCancelButtonTapped)
        viewStore.send(.setSelectedRoute(nil))
    }
    
    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        guard let viewStore = self.viewStore,
              let destination = self.destination else { return }
        
        switch sender.selectedSegmentIndex {
        case 0:
            viewStore.send(.fetchRoutes(destination, .automobile))
            viewStore.send(.setSelectedRoute(nil))
        case 1:
            viewStore.send(.fetchRoutes(destination, .walking))
            viewStore.send(.setSelectedRoute(nil))
        case 2:
            viewStore.send(.fetchRoutes(destination, .transit))
            viewStore.send(.setSelectedRoute(nil))
        default:
            break
        }
    }
    
}

extension RoutesSheetViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return routes.isEmpty ? 1 : routes.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if routes.isEmpty {
                // Show a "no routes" cell
                let cell = UITableViewCell(style: .default, reuseIdentifier: "NoRoutesCell")
                cell.textLabel?.text = "No routes to show"
                cell.textLabel?.textAlignment = .center
                cell.textLabel?.textColor = .secondaryLabel
                cell.selectionStyle = .none
                tableView.separatorStyle = .none
                return cell
            } else {
                // Normal route cell
                let cell = tableView.dequeueReusableCell(withIdentifier: "routesSheetTableViewCell", for: indexPath) as! RoutesSheetTableViewCell
                cell.viewStore = self.viewStore
                let route = routes[indexPath.row]
                cell.route = route
                tableView.separatorStyle = .singleLine
                // Distance
                let distanceText: String
                if route.distance < 1000 {
                    distanceText = String(format: "%.0f m", route.distance)
                } else {
                    distanceText = String(format: "%.1f km", route.distance / 1000)
                }

                // Travel time
                let travelTimeInMinutes = Int(route.expectedTravelTime / 60)

                // ETA
                let arrivalDate = Date().addingTimeInterval(route.expectedTravelTime)
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                let etaString = formatter.string(from: arrivalDate)

                // Assign values
                cell.timeLabel.text = "\(travelTimeInMinutes) min"
                cell.distanceLabel.text = "\(etaString) ETA – \(distanceText)"
                return cell
            }
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedRoute = routes[indexPath.row]
        self.viewStore?.send(.setSelectedRoute(selectedRoute))
        if let sheet = self.sheetPresentationController {
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = .init("customBottom")
            }
            addressLabel.isHidden = true
            segment.isHidden = true
            routesSheetTableCiew.isHidden = true
            destinationTitle.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        }
    }
}

extension RoutesSheetViewController: UISheetPresentationControllerDelegate {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        if sheetPresentationController.selectedDetentIdentifier?.rawValue == "customBottom" {
            addressLabel.isHidden = true
            segment.isHidden = true
            routesSheetTableCiew.isHidden = true
            destinationTitle.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        } else {
            // Show full content
            addressLabel.isHidden = false
            segment.isHidden = false
            routesSheetTableCiew.isHidden = false
        }
    }
}
