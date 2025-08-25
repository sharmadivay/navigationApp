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
    
    init(store: StoreOf<MainFeature>) {
        self.store = store
        self.viewStore = ViewStore(store,observe: {$0})
        super.init(nibName: nil, bundle: nil)
    }
    
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
    
    @IBOutlet weak var navigationBlankView: UIView!
    let locationManager = CLLocationManager()
    var resultVC: SearchLocationViewController!
    
    var currentPolyline: MKPolyline?
    var fullRouteCoordinates: [CLLocationCoordinate2D] = []
    var allRouteCoordinates: [[CLLocationCoordinate2D]] = []
    var currentRouteIndex: Int = 0   
    
    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
        
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        
        searchBar.addTarget(self, action: #selector(change), for: .editingChanged)
        
        //MARK: call functions
        setupMapView()
        setupSearchBar()
        bind()
        setupNavigationEtaStackView()
        
    }
    
    private func setupMapView() {
        mapView.showsUserLocation = true
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
    }
    
    private func bind() {
        viewStore
            .publisher
            .userLocation
            .sink {[weak self] userLocation in
                guard let self = self , let userLocation = userLocation else {return}
                self.zoomLocation(location: userLocation)
                if viewStore.isNavigation {
                    
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
                
                self.allRouteCoordinates = routes.map { route in
                    let polyline = route.polyline
                    var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                          count: polyline.pointCount)
                    polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
                    return coords
                }
                
                // Start with selected route
                self.currentRouteIndex = routes.firstIndex(where: { $0 == route }) ?? 0
                self.fullRouteCoordinates = self.allRouteCoordinates[self.currentRouteIndex]
                
                self.currentPolyline = route.polyline
                self.mapView.addOverlay(self.currentPolyline!)
                self.mapView.setVisibleMapRect(route.polyline.boundingMapRect,
                                               edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 120, right: 40),
                                               animated: true)
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
    
    func trimRoute(from userCoord: CLLocationCoordinate2D,
                   fullRoute: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard !fullRoute.isEmpty else { return [] }
        
        // Find nearest point in the route to the user
        let nearestIndex = fullRoute.enumerated().min(by: { a, b in
            let locA = CLLocation(latitude: a.element.latitude, longitude: a.element.longitude)
            let locB = CLLocation(latitude: b.element.latitude, longitude: b.element.longitude)
            let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
            return userLoc.distance(from: locA) < userLoc.distance(from: locB)
        })?.offset ?? 0
        
        // Slice the route from nearest point to the end
        var remaining = Array(fullRoute[nearestIndex..<fullRoute.count])
        
        // Insert current user location at the start (so polyline starts from user)
        remaining.insert(userCoord, at: 0)
        
        return remaining    }
    
    func updateActiveRoute(
        from userCoord: CLLocationCoordinate2D,
        allRoutes: [[CLLocationCoordinate2D]],
        currentRouteIndex: Int,
        switchThreshold: CLLocationDistance = 30
    ) -> (updatedCoords: [CLLocationCoordinate2D], newRouteIndex: Int) {
        
        guard !allRoutes.isEmpty else { return ([], currentRouteIndex) }
        let userLoc = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        
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
        // Default: stay on current route
        var chosenIndex = currentRouteIndex
        if let nearest = routeDistances.min(by: { $0.value < $1.value }) {
            let (nearestIndex, nearestDistance) = nearest
            if nearestIndex != currentRouteIndex && nearestDistance < switchThreshold {
                // Switch only if another route is closer than threshold
                chosenIndex = nearestIndex
            }
        }
        
        // --- 3. Trim the chosen route ---
        let chosenRoute = allRoutes[chosenIndex]
        guard !chosenRoute.isEmpty else { return ([], chosenIndex) }
        
        // Find nearest point index on chosen route
        let nearestIndex = chosenRoute.enumerated().min(by: { a, b in
            let locA = CLLocation(latitude: a.element.latitude, longitude: a.element.longitude)
            let locB = CLLocation(latitude: b.element.latitude, longitude: b.element.longitude)
            return userLoc.distance(from: locA) < userLoc.distance(from: locB)
        })?.offset ?? 0
        
        var remaining = Array(chosenRoute[nearestIndex..<chosenRoute.count])
        remaining.insert(userCoord, at: 0) // start at user
        
        return (remaining, chosenIndex)
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






