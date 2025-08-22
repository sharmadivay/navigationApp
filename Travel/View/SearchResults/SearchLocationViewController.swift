//
//  SearchLocationViewController.swift
//  Travel
//
//  Created by Divay Sharma on 19/08/25.
//
import UIKit
import MapKit
import ComposableArchitecture
import Combine

class SearchLocationViewController: UIViewController {
    
    @IBOutlet weak var searchLocationTableView: UITableView!
    var viewStore: ViewStoreOf<MainFeature>?
    var cancellables: Set<AnyCancellable> = []
    var searchResults:[MKMapItem] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        searchLocationTableView.delegate = self
        searchLocationTableView.dataSource = self
        guard let viewStore = viewStore else { return }
        viewStore
            .publisher
            .searchResults
            .sink {[weak self] searchResults in
                guard let self = self  else { return }
                self.searchResults = searchResults
                self.searchLocationTableView.reloadData()
            }
            .store(in: &cancellables)
    }
    
}

extension SearchLocationViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Search Results"
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "searchResultsCell") as! SearchLocationTableViewCell
        let location = searchResults[indexPath.row]
        
        //MARK: Calculate distance  
        if let currentLocation = self.viewStore?.userLocation {
            let placeLocation = CLLocation(latitude: location.placemark.coordinate.latitude,
                                           longitude: location.placemark.coordinate.longitude)
            
            let distanceInMeters = currentLocation.distance(from: placeLocation)
            
            // Format in km or meters
            let distanceString: String
            if distanceInMeters > 1000 {
                distanceString = String(format: "%.2f km", distanceInMeters / 1000)
            } else {
                distanceString = String(format: "%.0f m", distanceInMeters)
            }
            cell.distanceLabel.text = distanceString
        }
        
        cell.locationTitle.text = location.name
        cell.locationAddress.text = [
            location.placemark.locality,        // City
            location.placemark.administrativeArea // State
        ].compactMap(\.self).joined(separator: ", ")

        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewStore?.send(.setDestination(searchResults[indexPath.row]))
        self.searchResults = []
    }
    
}
