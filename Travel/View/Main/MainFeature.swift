//
//  Main.swift
//  Travel
//
//  Created by Divay Sharma on 19/08/25.
//
import Foundation
import ComposableArchitecture
import MapKit

struct MainFeature: Reducer {
    
    enum CancelID { case routeRefresh }
    
    enum modeOfTransport: String {
        case automobile
        case walking
        case transit
    }
    
    struct State: Equatable {
        var userLocation: CLLocation?
        var query: String = ""
        var searchResults: [MKMapItem] = []
        var destination: MKMapItem? = nil
        var routes: [MKRoute] = []
        var selectedRoute: MKRoute? = nil
        var isSheetPresented: Bool = false
        var isGoButtonTapped: Bool = false
        var transportMode: modeOfTransport = .automobile
        var isNavigation: Bool = false
        var refreshCounter: Int = 0
    }
    
    enum Action: Equatable {
        case updateUserLocation(CLLocation)
        case updateQuery(String)
        case performSearch
        case searchResponse(Result<[MKMapItem], NSError>)
        case resetResults
        case setDestination(MKMapItem)
        case fetchRoutes(MKMapItem,modeOfTransport)
        case setRoutes([MKRoute])
        case setSelectedRoute(MKRoute?)
        case setSheetCancelButtonTapped
        case setGoButtonTapped(MKRoute?)
        case isNavigationCrossButtonTapped
    }
    
    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .updateUserLocation(let location):
            state.userLocation = location
            return .none
        case .updateQuery(let query):
            state.query = query
            return .run{ send in
                try await Task.sleep(nanoseconds: 500_000_000)
                await send(.performSearch)
            }
        case .performSearch:
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = state.query
            request.resultTypes = .pointOfInterest
            guard let location = state.userLocation?.coordinate else { return .none }
            let region = MKCoordinateRegion(
                center: location,
                latitudinalMeters: 300,
                longitudinalMeters: 300
            )
            request.region = region
            return .run { send in
                do {
                    let response = try await MKLocalSearch(request: request).start()
                    await send(.searchResponse(.success(response.mapItems)))
                } catch {
                    await send(.searchResponse(.failure(error as NSError)))
                }
            }
        case let .searchResponse(.success(items)):
            state.searchResults = items
            return .none
        case .searchResponse(.failure):
            state.searchResults = []
            return .none
        case .resetResults:
            state.searchResults = []
            return .none
        case .setDestination(let destination):
            state.destination = destination
            state.isSheetPresented = true
//            state.isSheetCancelButtonTapped = false
            return .send(.fetchRoutes(destination , .automobile))
        case let  .fetchRoutes( destination , mode ):
            state.transportMode = mode
            guard let userLocation = state.userLocation else { return .none }
            let request = MKDirections.Request()
            request.destination = destination
            request.requestsAlternateRoutes = true
            request.transportType = state.transportMode.mapKitType
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
            return .run { send in
                do {
                      let response = try await MKDirections(request: request).calculate()
                      let routes = response.routes
                      await send(.setRoutes(routes))
                  } catch {
                      print("Route calculation failed: \(error.localizedDescription)")
                      await send(.setRoutes([]))
                  }
            }
        case .setRoutes(let routes):
            state.routes = routes
            state.isSheetPresented = true
            guard let destination = state.destination else { return .none}
            let mode = state.transportMode
            if state.isNavigation {
                guard let selectedRoute = state.selectedRoute else {
                    return .none
                }
                return .run { send in
                    for await _ in Timer.publish(every: 20, on: .main, in: .common).autoconnect().values {
                        await send(.setGoButtonTapped(selectedRoute))
                    }
                   
                }
                .cancellable(id: CancelID.routeRefresh, cancelInFlight: true)
            }else {
                return .run { send in
                    
                    for await _ in Timer.publish(every: 60, on: .main, in: .common).autoconnect().values {
                        await send(.fetchRoutes(destination, mode))
                        
                    }
                }
                .cancellable(id: CancelID.routeRefresh, cancelInFlight: true)
            }
        case .setSelectedRoute(let route):
            state.selectedRoute = route
            return .none
        case .setSheetCancelButtonTapped:
            state = MainFeature.State(userLocation: state.userLocation)
            return .cancel(id: CancelID.routeRefresh)
        case .setGoButtonTapped(let route):
            state.isNavigation = true
            state.isGoButtonTapped = true
            state.selectedRoute = route
            state.isSheetPresented = false
            state.refreshCounter += 1
            return .none
        case .isNavigationCrossButtonTapped:
            state = MainFeature.State(userLocation: state.userLocation)
            return .cancel(id: CancelID.routeRefresh)
        }
        
    }
    
}

extension MainFeature.modeOfTransport {
    var mapKitType: MKDirectionsTransportType {
        switch self {
        case .automobile: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        }
    }
}
