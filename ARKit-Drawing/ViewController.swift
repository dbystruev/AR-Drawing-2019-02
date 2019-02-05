import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController {

    @IBOutlet var sceneView: ARSCNView!
    
    let configuration = ARWorldTrackingConfiguration()
    
    var selectedNode: SCNNode?
    
    var placedNodes = [SCNNode]()
    var planeNodes = [SCNNode]()
    
    var lastPoint: CGPoint?
    let minimumDistance = CGFloat(40)
    
    var showPlaneOverlay = false {
        didSet {
            planeNodes.forEach { $0.isHidden = !showPlaneOverlay }
        }
    }
    
    enum ObjectPlacementMode {
        case freeform, plane, image
    }
    
    var objectMode: ObjectPlacementMode = .freeform {
        didSet {
            reloadConfiguration(removeAnchors: false)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfiguration(removeAnchors: false)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            objectMode = .freeform
        case 1:
            objectMode = .plane
        case 2:
            objectMode = .image
        default:
            break
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOptions" {
            let optionsViewController = segue.destination as! OptionsContainerViewController
            optionsViewController.delegate = self
        }
    }
}

extension ViewController: OptionsViewControllerDelegate {
    
    func objectSelected(node: SCNNode) {
        dismiss(animated: true, completion: nil)
        selectedNode = node
    }
    
    func togglePlaneVisualization() {
        dismiss(animated: true, completion: nil)
        showPlaneOverlay.toggle()
    }
    
    func undoLastObject() {
        guard let lastNode = placedNodes.last else { return }
        
        lastNode.removeFromParentNode()
        placedNodes.removeLast()
    }
    
    func resetScene() {
        dismiss(animated: true, completion: nil)
        reloadConfiguration(removeAnchors: true)
    }
}

// MARK: - ... Touches
extension ViewController {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let node = selectedNode else { return }
        guard let touch = touches.first else { return }
        
        switch objectMode {
        case .freeform:
            addNodeInFront(node)
        case .plane:
            let point = touch.location(in: sceneView)
            addNode(node, to: point)
        case .image:
            break
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard let node = selectedNode else { return }
        guard let touch = touches.first else { return }
        guard objectMode == .plane else { return }
        
        let point = touch.location(in: sceneView)
        
        if let lastPoint = lastPoint {
            let distance = sqrt(
                pow(point.x - lastPoint.x, 2) +
                pow(point.y - lastPoint.y, 2)
            )
            
            guard minimumDistance < distance else { return }
        }
        
        addNode(node, to: point)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        lastPoint = nil
    }
    
    func addNode(_ node: SCNNode, to point: CGPoint) {
        let results = sceneView.hitTest(point, types: [.existingPlaneUsingExtent])
        
        guard let match = results.first else { return }
        
        let transform = match.worldTransform
        
        node.simdTransform = transform
        
        addNodeToSceneRoot(node)
        lastPoint = point
    }
    
    func addNodeInFront(_ node: SCNNode) {
        guard let camera = sceneView.session.currentFrame?.camera else { return }
        
        var translation = matrix_identity_float4x4
        translation.columns.3.z = -0.2
        
        node.simdTransform = matrix_multiply(camera.transform, translation)
        
        addNodeToSceneRoot(node)
    }
    
    func addNodeToSceneRoot(_ node: SCNNode) {
        addNode(node, to: sceneView.scene.rootNode)
    }
}

// MARK: - ... Custom Methods
extension ViewController {
    func reloadConfiguration(removeAnchors: Bool) {
        configuration.planeDetection = [.horizontal]
        
        configuration.detectionImages = objectMode == .image ?
            ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) : nil
        
        let options: ARSession.RunOptions
        
        if removeAnchors {
            options = [.removeExistingAnchors]
            
            planeNodes.forEach { $0.removeFromParentNode() }
            planeNodes.removeAll()
            
            placedNodes.forEach { $0.removeFromParentNode() }
            placedNodes.removeAll()
        } else {
            options = []
        }
        
        sceneView.session.run(configuration, options: options)
    }
}

// MARK: - ... ARSCNViewDelegate Protocol
extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        print(#function, anchor)
        
        if let imageAnchor = anchor as? ARImageAnchor {
            nodeAdded(node, for: imageAnchor)
        } else if let planeAnchor = anchor as? ARPlaneAnchor {
            nodeAdded(node, for: planeAnchor)
        }
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor) {
        guard let selectedNode = selectedNode else { return }
        
        addNode(selectedNode, to: node)
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        let floor = createFloor(anchor: anchor)
        floor.isHidden = !showPlaneOverlay
        
        node.addChildNode(floor)
        planeNodes.append(floor)
    }
    
    func addNode(_ node: SCNNode, to parentNode: SCNNode) {
        let cloneNode = node.clone()
        parentNode.addChildNode(cloneNode)
        placedNodes.append(cloneNode)
    }
    
    func createFloor(anchor: ARPlaneAnchor) -> SCNNode {
        let width = CGFloat(anchor.extent.x)
        let height = CGFloat(anchor.extent.z)
        
        let node = SCNNode(geometry: SCNPlane(width: width, height: height))
        
        node.geometry?.firstMaterial?.diffuse.contents = #colorLiteral(red: 0.1764705926, green: 0.01176470611, blue: 0.5607843399, alpha: 1)
        node.eulerAngles.x = -.pi / 2
        node.opacity = 0.25
        
        return node
    }
}
