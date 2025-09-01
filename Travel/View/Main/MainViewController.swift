//
//  ViewController.swift
//  Travel
//
//  Created by Divay Sharma on 19/08/25.
//
import UIKit
import MapKit
import ComposableArchitecture
import CoreLocation
import Combine

class MainViewController: UIViewController {
    
    //MARK: store
    private let store: StoreOf<MainFeature>
    let viewStore: ViewStoreOf<MainFeature>
    private var cancellables: Set<AnyCancellable> = []
    
//    init(store: StoreOf<MainFeature>) {
//        self.store = store
//        self.viewStore = ViewStore(store,observe: {$0})
//        super.init(nibName: nil, bundle: nil)
//    }
    
    required init?(coder: NSCoder) {
        self.store = Store(
            initialState: MainFeature.State(),
            reducer: { MainFeature() }
        )
        self.viewStore = ViewStore(self.store, observe: { $0 })
        super.init(coder: coder)
    }
    
    //MARK: Outlets
    @IBOutlet weak var searchBar: UITextField!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var searchBarTrailingConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var NavigationEtaStackView: UIStackView!
    @IBOutlet weak var navigationCrossButton: UIButton!
    @IBOutlet weak var navigationTimeLabel: UILabel!
    @IBOutlet weak var navigationdistanceLabel: UILabel!
    
    @IBOutlet weak var blankView: UILabel!
    
    @IBOutlet weak var stepLabel: UILabel!
    @IBOutlet weak var stepsView: UIView!
    @IBOutlet weak var navigationBlankView: UIView!
    let locationManager = CLLocationManager()
    var resultVC: SearchLocationViewController!
    
    var currentPolyline: MKPolyline?
    var fullRouteCoordinates: [CLLocationCoordinate2D] = []
    var allRoutes: [MKRoute] = []
    var allRouteCoordinates: [[CLLocationCoordinate2D]] = []
    var currentRouteIndex: Int = 0
    var currentStepIndex: Int = 0
    var hasStartedMoving = false
    var startLocation: CLLocation?
    var activeRoute: MKRoute?
    var lastRerouteTime: Date? = nil
    var hasShownArrivalAlert = false

    
    override func viewDidLoad() {
        super.viewDidLoad()
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        
        //MARK: call functions
        setupMapView()
        setupSearchBar()
        bind()
        setupNavigationEtaStackView()
    }
    
    private func setupMapView() {
        mapView.delegate = self
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(minimizeSheet))
        tapGesture.numberOfTapsRequired = 1
        mapView.addGestureRecognizer(tapGesture)
        
        mapView.showsUserLocation = true
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
        mapView.showsUserTrackingButton = true
    }
    
    private func bind() {
        viewStore
            .publisher
            .userLocation
            .sink {[weak self] userLocation in
                guard let self = self , let userLocation = userLocation else {return}
               
                if viewStore.isNavigation {
                    viewStore.send(.setGoButtonTapped(viewStore.selectedRoute))
                    
                }else {
                    self.zoomLocation(location: userLocation)
                }
            }
            .store(in: &cancellables)
        viewStore
            .publisher
            .destination
            .sink { [weak self] destination in
                guard let self = self,let destination = destination else { return}
                let coordinates = destination.placemark.coordinate
                let location = CLLocation(latitude: coordinates.latitude,longitude: coordinates.longitude)
                self.zoomLocation(location: location,isAnnotation: true)
                self.removeResultVC()
                self.addAnnotation()
            }
            .store(in: &cancellables)
        viewStore
            .publisher
            .isSheetPresented
            .sink {[weak self] isSheetPresented in
                guard let self = self else {return}
                if isSheetPresented && !self.viewStore.isNavigation {
                    guard let destination = self.viewStore.destination else { return }
                    let storyboard = UIStoryboard(name: "Main", bundle: nil)
                    let sheetVC = storyboard.instantiateViewController(
                        withIdentifier: "RoutesSheetViewController"
                    ) as! RoutesSheetViewController
                    sheetVC.viewStore = self.viewStore
                    sheetVC.configure(destination: destination)
                    sheetVC.isModalInPresentation = true
                    searchBar.isHidden = true
                    DispatchQueue.main.async {
                        if let sheet = sheetVC.sheetPresentationController {
                            sheet.detents = [
                                .custom(identifier: .init("customBottom")) { context in
                                    return 120
                                },
                                .medium(),
                                .large()
                            ]
                            sheet.prefersGrabberVisible = true
                            sheet.preferredCornerRadius = 20
                            sheet.selectedDetentIdentifier = .medium
                            sheet.largestUndimmedDetentIdentifier = .large
                        }
                        self.present(sheetVC, animated: true)
                    }
                } else {
                    
                    if let presented = self.presentedViewController as? RoutesSheetViewController {
                        presented.dismiss(animated: true) {
                            self.mapView.removeAnnotations(self.mapView.annotations)
                            guard let userLocation = self.viewStore.userLocation else { return }
                            self.searchBar.isHidden = false
                            self.zoomLocation(location: userLocation)
                        }
                    }
                }
            }
            .store(in: &cancellables)
        viewStore.publisher.selectedRoute
            .sink { [weak self] selectedRoute in
                guard let self = self else { return }
                
                guard let route = selectedRoute else {
                    self.mapView.removeOverlays(self.mapView.overlays)
                    self.currentPolyline = nil
                    self.allRouteCoordinates = []
                    return
                }
                
                self.mapView.removeOverlays(self.mapView.overlays)
                self.searchBar.isHidden = true
                
                // Get all routes from store (instead of only selectedRoute)
                let routes = self.viewStore.routes // <- add this in your TCA state
                self.allRoutes = routes
                self.allRouteCoordinates = routes.map { route in
                    let polyline = route.polyline
                    var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                          count: polyline.pointCount)
                    polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
                    return self.densifyRoute(coords)
                }
                // Start with selected route
                self.currentRouteIndex = routes.firstIndex(where: { $0 == route }) ?? 0
                self.fullRouteCoordinates = self.allRouteCoordinates[self.currentRouteIndex]
                
                self.currentPolyline = route.polyline
                self.mapView.addOverlay(self.currentPolyline!)
                self.mapView.setVisibleMapRect(route.polyline.boundingMapRect,
                                               edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 120, right: 40),
                                               animated: true)
                
                if let destination = self.viewStore.destination {
                          let annotation = MKPointAnnotation()
                    print("hello")
                          annotation.coordinate = destination.placemark.coordinate
                          annotation.title = destination.placemark.name
                          annotation.subtitle = destination.placemark.title
                          self.mapView.addAnnotation(annotation)
                          self.mapView.selectAnnotation(annotation, animated: true)
                      }

            }
            .store(in: &cancellables)
        viewStore
            .publisher
            .isGoButtonTapped
            .sink {[weak self] isGoButtonTapped in
                guard let self = self else { return }
                if isGoButtonTapped {
                    // If a sheet is presented, dismiss it first
                    if let presentedSheet = self.presentedViewController as? RoutesSheetViewController {
                        presentedSheet.dismiss(animated: true) {
                            self.showNavigationEtaStack()
                            self.stepsView.isHidden = false
                            self.stepLabel.text = self.viewStore.routeSteps[1].instructions
                            if let destination = self.viewStore.destination {
                                      let annotation = MKPointAnnotation()
                                      annotation.coordinate = destination.placemark.coordinate
                                      annotation.title = destination.placemark.name
                                      annotation.subtitle = destination.placemark.title
                                      self.mapView.addAnnotation(annotation)
                                      self.mapView.selectAnnotation(annotation, animated: true)
                                  }
                            guard let userLocation = self.viewStore.userLocation else { return }
                            self.mapView.userTrackingMode = .follow
                         let camera = MKMapCamera(
                            lookingAtCenter: userLocation.coordinate,
                            fromDistance: 1800,
                            pitch: 0 ,
                            heading: userLocation.course
                         )
                            self.mapView.setCamera(camera, animated: true)
                           
                        }
                    } else {
                        self.showNavigationEtaStack()
                        self.stepsView.isHidden = false
//                        self.stepLabel.text = self.viewStore.routeSteps[0].instructions
                        self.stepLabel.text = self.viewStore.routeSteps[1].instructions
                    }
                    
                }
                else {
                    self.searchBar.isHidden = false
                    self.NavigationEtaStackView.isHidden = true
                    self.stepsView.isHidden = true
                }
            }
            .store(in: &cancellables)
        viewStore
            .publisher
            .refreshCounter
            .sink {[weak self] refreshCount in
                guard let self = self else { return }
                if refreshCount != 0 {
                    if let presentedSheet = self.presentedViewController as? RoutesSheetViewController {
                        presentedSheet.dismiss(animated: true) {
                            self.showNavigationEtaStack()
                        }
                    } else {
                        self.showNavigationEtaStack()
                    }
                }
                else {
                    self.searchBar.isHidden = false
                    self.NavigationEtaStackView.isHidden = true
                }
            }
            .store(in: &cancellables)
    }
            
    func updateActiveRoute(
        from userCoord: CLLocationCoordinate2D,
        allRoutes: [[CLLocationCoordinate2D]],
        allMkRoutes: [MKRoute],
        currentRouteIndex: Int,
        switchThreshold: CLLocationDistance = 30
    ) -> (updatedCoords: [CLLocationCoordinate2D], newRouteIndex: Int) {
        
        guard !allRoutes.isEmpty else { return ([], currentRouteIndex) }
        let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        
        // --- 0. Detect movement ---
           if startLocation == nil { startLocation = userLoc }
           let movedDistance = userLoc.distance(from: startLocation!)
           if movedDistance > 5 { hasStartedMoving = true }
        
        // --- 1. Calculate distance from user to each route ---
        var routeDistances: [Int: CLLocationDistance] = [:]
        
        for (i, route) in allRoutes.enumerated() {
            guard !route.isEmpty else { continue }
            
            // Find nearest point on this route
            let nearestDistance = route.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: userLoc)
            }.min() ?? Double.greatestFiniteMagnitude
            
            routeDistances[i] = nearestDistance
        }
        
        // --- 2. Choose the best route ---
        let chosenIndex = currentRouteIndex

        if hasStartedMoving {
            if viewStore.transportMode == .automobile {
                // ❌ Remove nearest route switching
                // ✅ Instead: only check if user is off the selected route
                if let currentDistance = routeDistances[currentRouteIndex], currentDistance > 40 {
                    if let destination = viewStore.destination {
                        print("🚗 Off driving route, recalculating…")
                        viewStore.send(.fetchRoutes(destination, viewStore.transportMode))
                    }
                }
            } else {
                // 🚶 Walking/transit (already same logic)
                if let currentDistance = routeDistances[currentRouteIndex], currentDistance > 50 {
                    if let destination = viewStore.destination {
                        print("🚶 Off walking route, recalculating…")
                        viewStore.send(.fetchRoutes(destination, viewStore.transportMode))
                    }
                }
            }
        }

        
        // --- 3. Trim the chosen route ---
        let chosenRoute = allRoutes[chosenIndex]
        let activeMKRoute = allMkRoutes[chosenIndex]
        guard !chosenRoute.isEmpty else { return ([], chosenIndex) }
        
        
        // Find nearest point index on chosen route
        let nearestIndex = chosenRoute.enumerated().min(by: { a, b in
            let locA = CLLocation(latitude: a.element.latitude, longitude: a.element.longitude)
            let locB = CLLocation(latitude: b.element.latitude, longitude: b.element.longitude)
            return userLoc.distance(from: locA) < userLoc.distance(from: locB)
        })?.offset ?? 0
        
        guard let neededRoute = viewStore.selectedRoute else { return ([], chosenIndex) }
        
        let remainingDistance = currentPolyline?.distance() ?? neededRoute.distance
        let avgSpeed = remainingDistance > 0
        ? neededRoute.expectedTravelTime / neededRoute.distance
              : 0
        let remainingTime = avgSpeed * remainingDistance
        let arrival = Date().addingTimeInterval(remainingTime)
        
        self.navigationTimeLabel.text = "\(Int(remainingTime / 60)) min"
//        let distanceText = String(format: "%.1f", remainingDistance / 1000)
        let distanceText: String
        if remainingDistance < 1000 {
            distanceText = String(format: "%.0f m", remainingDistance)
        } else {
            distanceText = String(format: "%.1f km", remainingDistance / 1000)
        }
        let arrivalDate = arrival
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let etaString = formatter.string(from: arrivalDate)
        
        self.navigationdistanceLabel.text = "\(distanceText) – \(etaString)"
        
        if chosenIndex != currentRouteIndex {
            currentStepIndex = 0
        }
        updateStep(for: userLoc, route: activeMKRoute)
        
        var remaining = Array(chosenRoute[nearestIndex..<chosenRoute.count])
        remaining.insert(userCoord, at: 0) // start at user
        
        return (remaining, chosenIndex)
    }
    
    func updateStep(for userLoc: CLLocation, route: MKRoute) {
        let steps = route.steps

           // --- Check if destination reached first ---
           if let destination = viewStore.destination {
               let destLoc = CLLocation(latitude: destination.placemark.coordinate.latitude,
                                        longitude: destination.placemark.coordinate.longitude)
               let distanceToDest = userLoc.distance(from: destLoc)
               print("distanceToDest \(distanceToDest)m")

               if distanceToDest < 50 && !hasShownArrivalAlert {
                   hasShownArrivalAlert = true
                   stepLabel.text = "You have arrived"
                   self.viewStore.send(.isNavigationCrossButtonTapped)
                   let alert = UIAlertController(
                       title: "Destination Reached 🎉",
                       message: "You have arrived at your destination.",
                       preferredStyle: .alert
                   )
                   alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                       self.viewStore.send(.isNavigationCrossButtonTapped)
                   })
                   present(alert, animated: true)
                   return // 🚨 stop here, don’t try to advance steps anymore
               }
           }

           // --- Normal step handling ---
           guard currentStepIndex < steps.count else {
               stepLabel.text = "You have arrived"
               return
           }

        var step = steps[currentStepIndex]

        // Skip silent steps (empty instruction, very short)
        while currentStepIndex < steps.count - 1 {
            let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            let len = step.polyline.distance()
            if !text.isEmpty || len > 5 { break }
            currentStepIndex += 1
            step = steps[currentStepIndex]
        }

        // --- Geometry ---
        let (cum, totalLen, coords) = step.polyline.cumulativeDistances()
        guard coords.count > 1 else {
            stepLabel.text = step.instructions.isEmpty ? "Continue" : step.instructions
            return
        }

        // --- Find nearest vertex ---
        var nearestIdx = 0
        var nearestDist = CLLocationDistance.greatestFiniteMagnitude
        for (i, coord) in coords.enumerated() {
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let d = userLoc.distance(from: loc)
            if d < nearestDist {
                nearestDist = d
                nearestIdx = i
            }
        }

        // --- Off-route detection with cooldown ---
           if nearestDist > 40 {
               let now = Date()
               if lastRerouteTime == nil || now.timeIntervalSince(lastRerouteTime!) > 20 {
                   print("🚨 Off route (\(nearestDist)m). Requesting new route...")
                   lastRerouteTime = now
                   if let destination = viewStore.destination {
                       viewStore.send(.fetchRoutes(destination, viewStore.transportMode))
                   }
               } else {
                   print("⏳ Off route but still in cooldown, skipping reroute")
               }
               return
           }

        // --- Progress by distance ---
        let progress = totalLen == 0 ? 0 : cum[nearestIdx] / totalLen

        // --- Completion thresholds ---
        let endCoord = coords.last!
        let endLoc = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
        let distToEnd = userLoc.distance(from: endLoc)

        let pctThreshold: Double = 0.85
        let distThreshold: CLLocationDistance = max(20, min(60, totalLen * 0.15))

        if (progress >= pctThreshold || distToEnd <= distThreshold),
           currentStepIndex < steps.count - 1 {
            currentStepIndex += 1
            print("➡️ Advanced to step \(currentStepIndex+1)/\(steps.count)")
        }

        // --- Update label ---
        if currentStepIndex < steps.count { let cur = steps[currentStepIndex]
            //Check distance to next step start
            let nextStepStart = cur.polyline.coordinate
            let distToNextStart = userLoc.distance(from: CLLocation(latitude: nextStepStart.latitude, longitude: nextStepStart.longitude))
            if distToNextStart > 200 {
                // Too far → generic continue instruction
                stepLabel.text = "⬆️ Continue" }
            else { // Close enough → show actual next step instruction
                let arrow = arrowFor(step: cur)
                let text = cur.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                stepLabel.text = arrow + (text.isEmpty ? "Continue" : text) }
        } else {
            stepLabel.text = "Continue"
        }
    }


    
    func densifyRoute(
        _ route: [CLLocationCoordinate2D],
        stepDistance: CLLocationDistance = 1
    ) -> [CLLocationCoordinate2D] {
        guard route.count > 1 else { return route }
        
        var denseRoute: [CLLocationCoordinate2D] = []
        
        for i in 0..<route.count-1 {
            let start = route[i]
            let end = route[i+1]
            
            // Add start
            if denseRoute.isEmpty {
                denseRoute.append(start)
            }
            
            // Distance between two points
            let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
            let distance = startLoc.distance(from: endLoc)
            
            // Number of extra points
            let steps = max(2, Int(distance / stepDistance))
            
            // Interpolate
            for s in 1...steps {
                let t = Double(s) / Double(steps)
                let lat = start.latitude + (end.latitude - start.latitude) * t
                let lon = start.longitude + (end.longitude - start.longitude) * t
                denseRoute.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        
        return denseRoute
    }
    
    private func showNavigationEtaStack() {
        UIView.animate(withDuration: 0.3) {
            self.NavigationEtaStackView.isHidden = false
            self.navigationBlankView.isHidden = false
            self.searchBar.isHidden = true
        }
        
        if let selectedRoute = self.viewStore.selectedRoute {
            let travelTimeInMinutes = Int(selectedRoute.expectedTravelTime / 60)
            self.navigationTimeLabel.text = "\(travelTimeInMinutes) min"
            
            let distanceText: String
            if selectedRoute.distance < 1000 {
                distanceText = String(format: "%.0f m", selectedRoute.distance)
            } else {
                distanceText = String(format: "%.1f km", selectedRoute.distance / 1000)
            }
            
            let arrivalDate = Date().addingTimeInterval(selectedRoute.expectedTravelTime)
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let etaString = formatter.string(from: arrivalDate)
            
            self.navigationdistanceLabel.text = "\(distanceText) – \(etaString)"
        } else {
            self.navigationTimeLabel.text = "-"
            self.navigationdistanceLabel.text = "-"
        }
        guard let location = self.viewStore.userLocation else { return }
        self.zoomLocation(location: location)
    }
    
    private func zoomLocation(location: CLLocation , isAnnotation: Bool = false) {
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: location.coordinate.latitude - 0.00050,
            longitude: location.coordinate.longitude
        )
        let center = isAnnotation ? adjustedCenter : location.coordinate
        let region = MKCoordinateRegion(center: center, latitudinalMeters: 200, longitudinalMeters: 200)
        mapView.setRegion(region, animated: true)
    }
    
    private func setupSearchBar() {
        let iconImageView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iconImageView.tintColor = .gray
        iconImageView.contentMode = .scaleAspectFit
        
        // padding around icon
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
        iconImageView.frame = CGRect(x: 5, y: 0, width: 20, height: 20)
        containerView.addSubview(iconImageView)
        
        searchBar.leftView = containerView
        searchBar.leftViewMode = .always
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        
        
        let storyBoard = UIStoryboard(name: "Main", bundle: nil)
        resultVC = storyBoard.instantiateViewController(identifier: "searchLocationViewController")
        resultVC.viewStore = self.viewStore
        
        searchBar.addTarget(self, action: #selector(change), for: .editingChanged)
        
        setupCancelButton()
    }
    
    private func setupCancelButton() {
        cancelButton.isHidden = true
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupNavigationEtaStackView() {
        NavigationEtaStackView.layer.cornerRadius = 16
        NavigationEtaStackView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        NavigationEtaStackView.layer.masksToBounds = true
        
        setupNavigationCrossButton()
    }
    
    private func setupNavigationCrossButton() {
        let largeConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
        let image = UIImage(systemName: "xmark.circle", withConfiguration: largeConfig)
        navigationCrossButton.setImage(image, for: .normal)
    }
    
    func removeResultVC() {
        guard let resultsVC = resultVC else { return }
        
        resultsVC.willMove(toParent: nil)
        resultsVC.view.removeFromSuperview()
        resultsVC.removeFromParent()
        
        self.blankView.isHidden = true
        self.cancelButton.isHidden = true
        self.searchBar.text = ""
        searchBar.resignFirstResponder()
        searchBarTrailingConstraint.constant = 16
        viewStore.send(.resetResults)
    }
    
    private func addAnnotation() {
        let annotation = MKPointAnnotation()
        guard let destination = viewStore.state.destination else { return }
        annotation.coordinate = destination.placemark.coordinate
        annotation.title = destination.placemark.name
        annotation.subtitle = destination.placemark.title
        mapView.addAnnotation(annotation)
        mapView.selectAnnotation(annotation, animated: true)
    }
    
    func arrowFor(step: MKRoute.Step) -> String {
        let text = step.instructions.lowercased()
        if text.contains("left") { return "⬅️ " }
        if text.contains("right") { return "➡️ " }
        if text.contains("roundabout") { return "⟳ " }
        if text.contains("continue") { return "⬆️ " }
        return "• "
    }
    
    @objc private func minimizeSheet() {
        if let sheetVC = self.presentedViewController as? RoutesSheetViewController,
           let sheet = sheetVC.sheetPresentationController {
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = .init("customBottom")
            }
        }
    }
    
    @IBAction func cancelButtonTapped(_ sender: Any) {
        searchBar.resignFirstResponder()
        searchBarTrailingConstraint.constant = 16
        removeResultVC()
    }
    @IBAction func navigationCrossButtontapped(_ sender: Any) {
        viewStore.send(.isNavigationCrossButtonTapped)
    }
    
    @objc func change() {
        guard let text = searchBar.text else {return}
        viewStore.send(.updateQuery(text))
    }
    
}






