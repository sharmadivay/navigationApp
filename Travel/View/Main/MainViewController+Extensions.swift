//
//  MainViewController+Extensions.swift
//  Travel
//
//  Created by Divay Sharma on 19/08/25.
//
import CoreLocation
import UIKit
import MapKit

extension MainViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        viewStore.send(.updateUserLocation(location))
        // Only update polyline while navigation is active
               if viewStore.state.isNavigation {
                   // Remove old polyline
                   if let current = currentPolyline {
                       mapView.removeOverlay(current)
                   }
                   
                   // Trim route
                   guard let userLocation = self.viewStore.userLocation else { return }
                   let updatedCoords = trimRoute(from: userLocation.coordinate,
                                                 fullRoute: fullRouteCoordinates)
                   
                   // Redraw remaining polyline
                   let newPolyline = MKPolyline(coordinates: updatedCoords, count: updatedCoords.count)
                   currentPolyline = newPolyline
                   mapView.addOverlay(newPolyline)
               }
        }

}

extension MainViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        addChild(resultVC)
        view.addSubview(resultVC.view)
        resultVC.didMove(toParent: self)
        // Position below the search bar
        resultVC.view.frame = CGRect(
            x: 0,
            y: searchBar.frame.maxY,
            width: view.bounds.width,
            height: view.bounds.height - searchBar.frame.maxY
            
        )
        self.blankView.isHidden = false
        self.cancelButton.isHidden = false
        self.searchBarTrailingConstraint.constant = self.cancelButton.bounds.width + 8
    }
    
}

extension MainViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
         if let polyline = overlay as? MKPolyline {
             let renderer = MKPolylineRenderer(polyline: polyline)
             renderer.strokeColor = .systemBlue
             renderer.lineWidth = 5
             return renderer
         }
         return MKOverlayRenderer(overlay: overlay)
     }

}
