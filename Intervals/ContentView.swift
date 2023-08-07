//
//  ContentView.swift
//  Intervals
//
//  Created by Chethan Shivaram on 11/13/22.
//

import SwiftUI
import AudioKit
import SoundpipeAudioKit
import AVFAudio
class Model: ObservableObject {
    
    let coordinateSpace = "CoordinateSpace"
    
    @Published var isDragged = false
    @Published var highlightedNumber: Int? = nil
    @Published var selectedNumber: Int? = nil
    
    /// Frames for individual picker items (from their respective `GeometryReader`).
    private var framesForNumbers: [Int: CGRect] = [:]
    
    func update(frame: CGRect, for number: Int) {
        framesForNumbers[number] = frame
    }
    
    /// Updates `highlightedNumber` according drag location.
    func update(dragLocation: CGPoint) {
        
        // Lookup if any frame contains drag location.
        for (eachNumber, eachFrame) in framesForNumbers {
            if eachFrame.contains(dragLocation) {
                
                // Publish.
                self.highlightedNumber = eachNumber
                return
            }
        }
        
        // Reset otherwise.
        self.highlightedNumber = nil
    }
    
    /// Updates `highlightedNumber` and `selectedNumber` according drop location.
    func update(isDragged: Bool) {
        
        // Publish.
        self.isDragged = isDragged
        
        if isDragged == false,
           let highlightedNumber = self.highlightedNumber {
            
            // Publish.
            self.selectedNumber = highlightedNumber
            self.highlightedNumber = nil
        }
    }
}
struct TouchesView: View {
    
    var model: Model
    @Binding var isDragged: Bool
    
    var body: some View {
        Rectangle()
            .foregroundColor(isDragged ? .orange : .yellow)
            .coordinateSpace(name: model.coordinateSpace)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.update(dragLocation: value.location)
                        model.update(isDragged: true)
                    }
                    .onEnded { state in
                        model.update(dragLocation: state.location)
                        model.update(isDragged: false)
                    }
                )
    }
}
struct ContentView: View {
    @StateObject var model = Model()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Honeycomb(model: model,
                      hexSize:  CGSize(width: 75, height: 75))
            .scaleEffect(0.7)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static var previews: some View {
        ContentView()
            .previewInterfaceOrientation(.landscapeRight)
    }
}


struct Honeycomb: View {
    @ObservedObject var model: Model
    let cols: Int
    let spacing: CGFloat = 5
    let hexSize: CGSize
    let hexagonWidth: CGFloat
        
    @State var tappedIdxs: Set<Int> = []
    let audioEngine = AudioEngine()
    let oscillator = DynamicOscillator(amplitude: 0)
    let notes: [Note]
    
    init(model: Model, hexSize: CGSize) {
        self.model = model
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, options: .defaultToSpeaker)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let error as NSError {
            print("AVAudioSession error: \(error.localizedDescription)")
        }
        
        let bounds = UIScreen.main.bounds
        let width = bounds.size.width
        let height = bounds.size.height
        
        self.hexSize = hexSize
        self.hexagonWidth = (hexSize.width / 2) * cos(.pi / 6) * 2
        cols = 13
        self.notes = Note.makeNotes(numCols: cols, numRows: 6)
    }
    
    var body: some View {
        let gridItems = Array(repeating: GridItem(.fixed(hexagonWidth), spacing: spacing), count: cols)

        LazyVGrid(columns: gridItems, spacing: spacing) {
            ForEach(notes) { note in
                VStack(spacing: 0) {
                    Color.gray.opacity(0.4)
                        .frame(width: hexSize.width, height: hexSize.height)
                        .overlay(
                            Group {
                                if tappedIdxs.contains(note.idx) {
                                    Color.blue.opacity(0.7)
                                        .blur(radius: 35)
                                } else {
                                    EmptyView()
                                }
                            }
                        )
                        .clipShape(PolygonShape(sides: 6).rotation(Angle.degrees(90)))
                        .offset(x: isEvenRow(note.idx) ? 0 : hexagonWidth / 2 + (spacing/2))
                }
                .frame(width: hexagonWidth, height: hexSize.height * 0.75)
                .overlay(GeometryReader { geometry -> Color  in
                                self.model.update(
                                    frame: geometry.frame(in: .named(self.model.coordinateSpace)),
                                    for: note.idx
                                )
                                return Color.clear
                            })
                .pressAction {
                    oscillator.frequency = AUValue(note.frequency)
                    oscillator.amplitude = 0.5
                    oscillator.start()
                    tappedIdxs.insert(note.idx)
                } onRelease: {
                    oscillator.stop()
                    tappedIdxs.remove(note.idx)
                }
                
                
            }
        }
        .frame(width: (hexagonWidth + spacing) * CGFloat(cols-1))
        .onChange(of: model.highlightedNumber) { num in
            print(num)
        }
        .onAppear {
            audioEngine.output = oscillator
            do {
                try audioEngine.start()
            } catch {
                print("penis butt")
            }
            
        }
    }
    
    func isEvenRow(_ idx: Int) -> Bool { (idx / cols) % 2 == 0 }
}

struct Note: Identifiable {
    let id = UUID()
    let frequency: CGFloat
    let idx: Int
}

extension Note {
    static func makeNotes(numCols: Int, numRows: Int) -> [Note] {
        let numNotes = numCols*numRows
        var frequencies: [CGFloat] = Array(repeating: 0.0, count: numNotes)
        let a = pow(2.0, 1.0/12.0)
        let f_0: Double = 440
        for n in (0)..<(numNotes) {
            let frequency = f_0*pow(a, Double(n-50))
            let quotient = n / numCols
            print(quotient)
            let remainder = n % numCols
            frequencies[numNotes-((quotient+1)*numCols)+remainder] = frequency
        }
        print(frequencies)
        return frequencies.enumerated().map { Note(frequency: $1, idx: $0) }
    }
}

struct PolygonShape: Shape {
    var sides: Int
    
    func path(in rect: CGRect) -> Path {
        let h = Double(min(rect.size.width, rect.size.height)) / 2.0
        let c = CGPoint(x: rect.size.width / 2.0, y: rect.size.height / 2.0)
        var path = Path()
        
        for i in 0..<sides {
            let angle = (Double(i) * (360.0 / Double(sides))) * Double.pi / 180
            
            let pt = CGPoint(x: c.x + CGFloat(cos(angle) * h), y: c.y + CGFloat(sin(angle) * h))
            
            if i == 0 {
                path.move(to: pt) // move to first vertex
            } else {
                path.addLine(to: pt) // draw line to next vertex
            }
        }
        
        path.closeSubpath()
        
        return path
    }
}


struct PressActions: ViewModifier {
   var onPress: () -> Void
   var onRelease: () -> Void
   
   func body(content: Content) -> some View {
       content
           .simultaneousGesture(
               DragGesture(minimumDistance: 0)
                   .onChanged({ _ in
                       onPress()
                   })
                   .onEnded({ _ in
                       onRelease()
                   })
           )
   }
}

extension View {
    func pressAction(onPress: @escaping (() -> Void), onRelease: @escaping (() -> Void)) -> some View {
        modifier(PressActions(onPress: {
            onPress()
        }, onRelease: {
            onRelease()
        }))
    }
}
