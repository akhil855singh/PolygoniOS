//
//  ViewController.swift
//  PolygonPocUIkit
//
//  Created by Akhil on 3/19/25.
//

import UIKit
import MapKit

class PolygonPopoverView: UIView {
    
    enum ArrowDirection {
        case up
        case down
    }

    private let contentView = UIView()
    private let arrowSize = CGSize(width: 20, height: 10)
    private var arrowDirection: ArrowDirection = .down
    private var tapPoint: CGPoint = .zero  // In superview coordinate space

    init(title: String, id: String, direction: ArrowDirection, tapPointInSuperview: CGPoint) {
        super.init(frame: .zero)
        self.tapPoint = tapPointInSuperview
        self.arrowDirection = direction
        setupView(title: title, id: id)
    }

    private func setupView(title: String, id: String) {
        backgroundColor = .clear

        // Bubble
        contentView.backgroundColor = .black
        contentView.layer.cornerRadius = 16
        contentView.layer.masksToBounds = true
        addSubview(contentView)

        // Labels
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.textColor = .white

        let subtitleLabel = UILabel()
        subtitleLabel.text = "POLYGON ID"
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .gray

        let idLabel = UILabel()
        idLabel.text = id
        idLabel.font = .boldSystemFont(ofSize: 16)
        idLabel.textColor = .white

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, idLabel])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let arrowPath = UIBezierPath()
        let localTapX = tapPoint.x - frame.minX
        let startX = min(max(localTapX - arrowSize.width / 2, 15), bounds.width - arrowSize.width - 15)
        if arrowDirection == .down {
            arrowPath.move(to: CGPoint(x: startX, y: bounds.height - arrowSize.height))
            arrowPath.addLine(to: CGPoint(x: startX + arrowSize.width / 2, y: bounds.height))
            arrowPath.addLine(to: CGPoint(x: startX + arrowSize.width, y: bounds.height - arrowSize.height))
        } else {
            arrowPath.move(to: CGPoint(x: startX, y: arrowSize.height))
            arrowPath.addLine(to: CGPoint(x: startX + arrowSize.width / 2, y: 0))
            arrowPath.addLine(to: CGPoint(x: startX + arrowSize.width, y: arrowSize.height))
        }

        arrowPath.close()

        let arrowLayer = CAShapeLayer()
        arrowLayer.path = arrowPath.cgPath
        arrowLayer.fillColor = UIColor.black.cgColor
        layer.sublayers?.removeAll(where: { $0 is CAShapeLayer }) // Remove old arrows
        layer.addSublayer(arrowLayer)

        layoutContent()
    }

    private func layoutContent() {
        let arrowHeight = arrowSize.height
        if arrowDirection == .down {
            contentView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - arrowHeight)
        } else {
            contentView.frame = CGRect(x: 0, y: arrowHeight, width: bounds.width, height: bounds.height - arrowHeight)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class MetalPolygonRenderer: MKOverlayRenderer {
    var fillColor: UIColor = .black
    var strokeColor: UIColor = .black
    var lineWidth: CGFloat = 2.0

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
            
            guard let polygon = overlay as? MKPolygon else { return }
            
            let path = UIBezierPath()
            let points = polygon.points()
            let pointCount = polygon.pointCount
            
            guard pointCount > 1 else { return }
            
            let firstPoint = point(for: points[0])
            path.move(to: firstPoint)
            
            for i in 1..<pointCount {
                let nextPoint = point(for: points[i])
                path.addLine(to: nextPoint)
            }
            path.close()
            
            // Fill Polygon
            context.setFillColor(fillColor.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
            
            // Stroke Polygon
            context.setStrokeColor(strokeColor.cgColor)
            context.setLineWidth(lineWidth / zoomScale)
            context.addPath(path.cgPath)
            context.strokePath()
        }
    
    func contains(_ mapPoint: MKMapPoint) -> Bool {
        guard let polygon = overlay as? MKPolygon else { return false }

            let point = self.point(for: mapPoint)

            // Convert polygon coordinates to CGPath
            let path = CGMutablePath()
            let coords = polygon.coordinatesForMetalPolygon

            if let first = coords.first {
                path.move(to: self.point(for: MKMapPoint(first)))
                for coord in coords.dropFirst() {
                    path.addLine(to: self.point(for: MKMapPoint(coord)))
                }
                path.closeSubpath()
            }

            return path.contains(point)
        }
}

struct Geometry: Decodable {
    let type: String
    let coordinates: [[[Double]]]
}

struct PolygonResponse: Decodable {
    let geometry: Geometry
    let status: Int
    let id: String
}

struct PolygonData: Hashable {
    static func == (lhs: PolygonData, rhs: PolygonData) -> Bool {
        return lhs.polygon == rhs.polygon
    }
    
    let polygon: MKPolygon
    let status: Int
    let id: String
    let boundingMapRect: MKMapRect

        func hash(into hasher: inout Hasher) {
            hasher.combine(boundingMapRect.origin.x)
            hasher.combine(boundingMapRect.origin.y)
            hasher.combine(boundingMapRect.size.width)
            hasher.combine(boundingMapRect.size.height)
        }
}

class ViewController: UIViewController, MKMapViewDelegate {
    
    typealias MapBound = (minLat: Double, minLng: Double, maxLat: Double, maxLng: Double)
    
    private var mapView: MKMapView!
    private var polygonCache: [String: [PolygonData]] = [:] // Cache for polygonsData
    private var allPolygonsData: [PolygonData] = [] // all polygons
    private var lastBounds: MapBound? // Store the bounds of the last API call
    private let debounceDelay = 0.5 // 0.5 second debounce delay
    private var debounceTimer: Timer?
    private var fetchPolygonsWorkItem: DispatchWorkItem?
    private var visitedBounds:[String] = []
    private var renderedPolygons: Set<String> = [] // rendered polygons
    private var isZoomingORPanning: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMapView()
    }
    
    private func debounceGettingPolygons() {
        guard !isZoomingORPanning else { return } // Skip updates while interacting

        debounceTimer?.invalidate() // Cancel any previous timer
        
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.loadPolygonsInView() // 🔹 API Call after 500ms of inactivity
        }
    }

    private func setupMapView() {
        mapView = MKMapView(frame: view.bounds)
        mapView.delegate = self
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)

        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 28.5383, longitude: -81.3792),
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
        mapView.setRegion(initialRegion, animated: true)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
    }
    
    @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
        let tapPoint = gesture.location(in: mapView)
        let coordinate = mapView.convert(tapPoint, toCoordinateFrom: mapView)
        let mapPoint = MKMapPoint(coordinate)
        
        for overlay in mapView.overlays {
            guard let polygon = overlay as? MKPolygon else { continue }
            if let renderer = mapView.renderer(for: polygon) as? MetalPolygonRenderer {
                if renderer.contains(mapPoint) {
                    // Tapped polygon!
                    showPopover(for: polygon, at: coordinate)
                    break
                }
            }
        }
    }
    
    private func clampedPopoverFrame(for point: CGPoint, in container: UIView, popoverSize: CGSize, padding: CGFloat = 8) -> CGRect {
        let width = popoverSize.width
        let height = popoverSize.height
        
        let shouldShowAbove = point.y > height + padding
        var originY = shouldShowAbove
        ? point.y - height - 10  // show above tap
        : point.y + 10

        var originX = point.x - width / 2

        // Clamp X
        if originX < padding {
            originX = padding
        } else if originX + width > container.bounds.width - padding {
            originX = container.bounds.width - width - padding
        }

        // Clamp Y (try above, fallback to below if needed)
        if originY < padding {
            originY = point.y + 10 // show below the tap point instead
            if originY + height > container.bounds.height - padding {
                originY = container.bounds.height - height - padding
            }
        }

        return CGRect(x: originX, y: originY, width: width, height: height)
    }
    
    private func showPopover(for polygon: MKPolygon, at coordinate: CLLocationCoordinate2D) {
        
        let point = mapView.convert(coordinate, toPointTo: mapView)
        
        // Clean up existing popover if any
        mapView.subviews.filter { $0 is PolygonPopoverView }.forEach { $0.removeFromSuperview() }
        
        let polygonData = getPolygonDataForPolygon(polygon)
        let title = getTitleBasedOnStatus(polygonData?.status ?? 1)
        let id = polygonData?.id ?? "Unknown"
        
            let popoverSize = CGSize(width: 240, height: 120)
            
            var arrowDirection: PolygonPopoverView.ArrowDirection = .down
        let targetFrame = clampedPopoverFrame(for: point, in: mapView, popoverSize: popoverSize)

            // If the Y position was adjusted to show below instead of above, use .up arrow
        if targetFrame.origin.y > point.y {
                arrowDirection = .up
            }

        let popover = PolygonPopoverView(title: title, id: id, direction: arrowDirection, tapPointInSuperview: point)
            popover.frame = targetFrame
        popover.translatesAutoresizingMaskIntoConstraints = true
        mapView.addSubview(popover)
        
    }
    
    private func approximateZoomLevel() -> Int {
        let maxZoomSpan = 180.0 // Earth's latitude range
        let zoomScale = maxZoomSpan / mapView.region.span.latitudeDelta
        return Int(log2(zoomScale)) // Converts to Google Maps' zoom scale
    }
    
    private func loadPolygonsInView() {
        // Check zoom level
        guard !isZoomingORPanning else { return } // Skip updates while interacting
        print("zoom level: \(approximateZoomLevel())", Date())
        if approximateZoomLevel() <= 7 { return }

            let visibleMapRect = mapView.visibleMapRect
            
            let boundingBoxKey = createBoundingBoxKey(visibleMapRect)
            if (polygonCache[boundingBoxKey] != nil) {
                //updateVisiblePolygons()
                print("polygons present in cache, skipping fetch...");
                return
            }
            
            let bounds = getVisibleMapRectWithRoundedCoordinates(visibleMapRect)
            
            
             if (lastBounds != nil) &&
                    isBoundsInside(minLat: Int(bounds.minLat), minLng: Int(bounds.minLng), maxLat: Int(bounds.maxLat), maxLng: Int(bounds.maxLng))
             {
             print("Bounds are inside last bounds, skipping...");
             return
             }
             
            
            if visitedBounds.contains(boundingBoxKey) {
                print("Bounds already visited, skipping...", visitedBounds)
                return
            }
            
            
            createSubBoundsAndThenFetchPolygons(mapRect: visibleMapRect, boxKey: boundingBoxKey, completion: { [weak self] (polygonsData, boxKey, lastBound) in
                guard let self = self else { return }
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    
                    if let polygons = polygonsData {
                            allPolygonsData.append(contentsOf: polygons)
                        if lastBound != nil {
                            updateVisiblePolygons(polygons, boxKey: boxKey, bound: lastBound)
                        }
                        else {
                            updateVisiblePolygons(polygons, boxKey: "", bound: nil)
                        }
                    }
                }
             })
             
         
             
            
            
        /*
        fetchPolygons(minLat: bounds.minLat, minLong: bounds.minLng, maxLat: bounds.maxLat, maxLong: bounds.maxLng, completion: { [weak self] polygonResponse  in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let polygonsData = polygonResponse.compactMap { response in
                    let points = response.geometry.coordinates.first?.map {
                        CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
                    } ?? []
                    //douglas peucker called to minimize the latlongs
                    //let simplifiedPoints = self?.douglasPeucker(points: points, epsilon: 0.0001)
                    let polygon = MKPolygon(coordinates: points, count: points.count)
                    return PolygonData(polygon: polygon, status: response.status, id: response.id, boundingMapRect: visibleMapRect)
                }
                if polygonsData.isEmpty {
                    return
                }
                
                visitedBounds.append(boundingBoxKey)
                
                    //let cachedPolygons = polygonCache[boundingBoxKey] ?? []
                    polygonCache[boundingBoxKey] = []
                allPolygonsData.append(contentsOf: polygonsData)
                    updateVisiblePolygons()
            }
            })
         */
            
         
    }
    
    private func isBoundsInside(minLat: Int, minLng: Int, maxLat: Int, maxLng: Int) -> Bool {
        return minLat >= Int(lastBounds?.minLat ?? 0) &&
        minLng >= Int(lastBounds?.minLng ?? 0) &&
        maxLat <= Int(lastBounds?.maxLat ?? 0) &&
        maxLng <= Int(lastBounds?.maxLng ?? 0)
          
    }
    
    private func getVisibleMapRectWithRoundedCoordinates(_ mapRect: MKMapRect) -> (minLat: Double, minLng: Double, maxLat: Double, maxLng: Double) {
        let region = MKCoordinateRegion(mapRect)
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2
        return (minLat, minLng, maxLat, maxLng)
    }
    
    private func createBoundingBoxKey(_ mapRect: MKMapRect) -> String {
        let rect = getVisibleMapRectWithRoundedCoordinates(mapRect)
        return "\(floor(rect.minLat)),\(floor(rect.minLng)),\(ceil(rect.maxLat)),\(ceil(rect.maxLng))"
    }
    
    private func debounceFetchPolygons() {
            fetchPolygonsWorkItem?.cancel()
            
            let workItem = DispatchWorkItem { [weak self] in
                self?.loadPolygonsInView()
            }
            
            fetchPolygonsWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
        }
    
    private func createSubBoundsAndThenFetchPolygons(mapRect: MKMapRect, boxKey: String, completion: @escaping ([PolygonData]?, String, MapBound?) -> Void) {
        var index = 0
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            let bounds = getVisibleMapRectWithRoundedCoordinates(mapRect)
            let subBounds = generateSubBounds(minLat: bounds.minLat, minLng: bounds.minLng, maxLat: bounds.maxLat, maxLng: bounds.maxLng, numDivisions: 3)
            for bound in subBounds {
                index += 1
                fetchPolygons(minLat: bound.minLat, minLong: bound.minLng, maxLat: bound.maxLat, maxLong: bound.maxLng, completion: { polygonResponse in
                    let polygonsData = polygonResponse.compactMap { response in
                        let points = response.geometry.coordinates.first?.map {
                            CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
                        } ?? []
                        let polygon = MKPolygon(coordinates: points, count: points.count)
                        return PolygonData(polygon: polygon, status: response.status, id: response.id, boundingMapRect: mapRect)
                    }
                    completion(polygonsData, boxKey, (index == subBounds.count) ? bounds : nil)
                })
            }
        }
    }
    
    private func generateSubBounds(minLat: Double, minLng: Double, maxLat: Double, maxLng: Double, numDivisions: Int) -> [(minLat: Double, minLng: Double, maxLat: Double, maxLng: Double)] {
        // Ensure min < max for lat and lng
        let correctedMinLat = min(minLat, maxLat)
        let correctedMaxLat = max(minLat, maxLat)
        let correctedMinLng = min(minLng, maxLng)
        let correctedMaxLng = max(minLng, maxLng)

        let sqrtDivisions = ceil(sqrt(Double(numDivisions)))
        let latStep = (correctedMaxLat - correctedMinLat) / sqrtDivisions
        let lngStep = (correctedMaxLng - correctedMinLng) / sqrtDivisions

        var subBounds: [(minLat: Double, minLng: Double, maxLat: Double, maxLng: Double)] = []

        var lat = correctedMinLat
        while lat < correctedMaxLat {
            var lng = correctedMinLng
            while lng < correctedMaxLng {
                let nextLat = min(lat + latStep, correctedMaxLat)
                let nextLng = min(lng + lngStep, correctedMaxLng)

                subBounds.append((minLat: lat, minLng: lng, maxLat: nextLat, maxLng: nextLng))

                lng += lngStep
            }
            lat += latStep
        }

        return subBounds
    }
    
//    private func triggerPolygonFetching() {
//            debounceTimer?.invalidate()
//            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
//                self?.createSubBoundsAndThenFetchPolygons()
//            }
//        }

    private func fetchPolygons(minLat: Double, minLong: Double, maxLat: Double, maxLong: Double, completion: @escaping ([PolygonResponse]) -> Void) {
        guard !isZoomingORPanning else { return } // Skip updates while interacting
        guard let url = URL(string: "http://192.168.0.230:6010/polygons?minLat=\(minLat)&minLng=\(minLong)&maxLat=\(maxLat)&maxLng=\(maxLong)") else { return }
        print("data called now",Date())
        print("url for fetching polygons",url)
        DispatchQueue.global(qos: .background).async {
            URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
                guard let self = self, let data = data, !isZoomingORPanning, error == nil else { return }
                do {
                    let polygonResponses = try JSONDecoder().decode([PolygonResponse].self, from: data)
                        completion(polygonResponses)
                    print("data arrived now",Date())
                }
                catch {
                    print("Failed to decode JSON: \(error)")
                    
                }
            }.resume()
        }
    }
    
    /*
    
    private func processPolygons(_ polygonResponses: [PolygonResponse]) {
        if polygonResponses.count > 0 {
            processBatch(polygonResponses)
        }
    }
    
    private func processBatch(_ remainingPolygons: [PolygonResponse]) {
        var batch: [PolygonData] = []
        var polygonsRemaining = remainingPolygons
        
        while !polygonsRemaining.isEmpty && batch.count < batchSize {
            let response = polygonsRemaining.removeFirst()
            
            guard response.geometry.type == "Polygon" else { continue }
            
            let points = response.geometry.coordinates.first?.map {
                CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
            } ?? []
            
            if points.count > 0 {
                let polygon = MKPolygon(coordinates: points, count: points.count)
                let polygonData = PolygonData(polygon: polygon, status: response.status, boundingMapRect: polygon.boundingMapRect)
                batch.append(polygonData)
            }
        }
        
        if !batch.isEmpty {
            allPolygonsData.append(contentsOf: batch)
            updateVisiblePolygons()
            
            // Continue processing the next batch with a slight delay for smooth rendering.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.processBatch(polygonsRemaining)
            }
        }
    }
     */
    
    private func updateVisiblePolygons(_ polygons: [PolygonData], boxKey: String, bound:MapBound?) {
       
        guard !isZoomingORPanning else { return } // Skip updates while interacting
        if allPolygonsData.count > 0 {
            let visiblePolygons = polygons.filter { self.mapView.visibleMapRect.intersects($0.boundingMapRect) }
            if boxKey.isEmpty {
                loadPolygonsInBatches(visiblePolygons, boxKey: "", bound: bound)
            } else {
                loadPolygonsInBatches(visiblePolygons, boxKey: boxKey, bound: bound)
            }
        }
    }
    
    func loadPolygonsInBatches(_ allPolygons: [PolygonData], batchSize: Int = 500, boxKey: String, bound:MapBound?) {
        let chunks = allPolygons.chunked(into: batchSize)
        var index = 0
        
        for chunk in chunks {
            index = index + 1
            DispatchQueue.global(qos: .default).sync { [weak self] in
                guard let self = self else { return }
                loadBatchRecursively(chunk: chunk)
                usleep(300_000)
            }
            if index == chunks.count {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    visitedBounds.append(boxKey)
                    polygonCache[boxKey] = []
                    lastBounds = bound
                }
            }
            print("✅ Loaded batch \(index)/\(chunks.count)", Date())
        }
         
    }
    
    private func loadBatchRecursively(chunk: [PolygonData]) {
            print("isZoomingORPanning before", isZoomingORPanning)
            guard !isZoomingORPanning else {
                return
            }
        
        let newPolygons = chunk.filter { !self.renderedPolygons.contains($0.id) }
                
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else { return }
                print("isZoomingORPanning after", isZoomingORPanning)
                guard !isZoomingORPanning else {
                    return
                }
                self.mapView.addOverlays(newPolygons.map { $0.polygon })
                }
        
        for polygon in chunk {
            self.renderedPolygons.insert(polygon.id)
        }
    }
    
    private func getPolygonDataForPolygon(_ polygon: MKPolygon) -> PolygonData? {
        return self.allPolygonsData.first(where: {
            $0.polygon == polygon
        })
    }
    
    private func getColorBasedOnStatus(_ status: Int) -> UIColor {
        switch status {
        case 1,7,9,10:
            return .red
        case 2:
            return .blue
        case 3:
            return .green
        case 4:
            return .yellow
        case 5:
            return .purple
        case 6:
            return .brown
        case 8:
            return .purple
            
        default:
            return .black
        }
    }
    
    private func getTitleBasedOnStatus(_ status: Int) -> String {
        switch status {
        case 1:
            return "Low Population"
        case 2:
            return "Best"
        case 3,5,6:
            return "Good"
        case 4:
            return "OK - Termite"
        case 7,9,10:
            return "Do not knock"
        case 8:
            return "OK"
        default:
            return "OK"
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        
            if let polygon = overlay as? MKPolygon {
                let renderer = MetalPolygonRenderer(overlay: polygon)
                    if let polygonData = self.getPolygonDataForPolygon(polygon) {
                        let rendererColor = self.getColorBasedOnStatus(polygonData.status)
                            renderer.fillColor = rendererColor.withAlphaComponent(0.3)
                            renderer.strokeColor = rendererColor
                        renderer.lineWidth = 0.5
                    }
                    else {
                            renderer.fillColor = UIColor.black.withAlphaComponent(0.3)
                            renderer.strokeColor = UIColor.black
                        renderer.lineWidth = 0.5
                    }
                return renderer
        }
         
        return MKOverlayRenderer()
    }
    
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        isZoomingORPanning = true
        print("gesture began")
        mapView.subviews.filter { $0 is PolygonPopoverView }.forEach { $0.removeFromSuperview() }
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        isZoomingORPanning = false
        print("gesture ended")
        debounceGettingPolygons()
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension MKPolygon {
    var coordinatesForMetalPolygon: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: self.pointCount)
        self.getCoordinates(&coords, range: NSRange(location: 0, length: self.pointCount))
        return coords
    }
}


