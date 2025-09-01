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
        if viewStore.isNavigation {
                   let (updatedCoords, newIndex) = updateActiveRoute(
                       from: location.coordinate,
                       allRoutes: allRouteCoordinates,
                       allMkRoutes: allRoutes,
                       currentRouteIndex: currentRouteIndex,
                       switchThreshold: 50
                   )
                   
                   currentRouteIndex = newIndex
                   
                   // Replace polyline with trimmed one
                   if let current = currentPolyline {
                       mapView.removeOverlay(current)
                   }
            
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
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}


extension MKPolyline {
  func distance() -> CLLocationDistance {
    var total: CLLocationDistance = 0
    var coords = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
    getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
    for i in 0..<(coords.count-1) {
      let a = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
      let b = CLLocation(latitude: coords[i+1].latitude, longitude: coords[i+1].longitude)
      total += a.distance(from: b)
    }
    return total
  }
    
    func cumulativeDistances() -> ([CLLocationDistance], CLLocationDistance, [CLLocationCoordinate2D]) {
           guard pointCount > 1 else { return ([], 0, []) }
           var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
           getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
           var cum = [CLLocationDistance](repeating: 0, count: coords.count)
           var total: CLLocationDistance = 0
           for i in 1..<coords.count {
               let a = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
               let b = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
               total += a.distance(from: b)
               cum[i] = total
           }
           return (cum, total, coords)
       }
    
    func closestDistance(to location: CLLocation) -> CLLocationDistance {
           var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
           getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
           return coords.map {
               CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location)
           }.min() ?? .greatestFiniteMagnitude
       }
}
