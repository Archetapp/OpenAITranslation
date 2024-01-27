//
//  ViewModel.swift
//  LiveTranslation
//
//  Created by Jared Davidson on 1/27/24.
//

import Foundation
import SwiftUI
import OpenAI
import AVFoundation

struct Translation: Codable, Identifiable {
    var id: String = UUID().uuidString
    var user: String
    var original: String
    var translated: String
    var originalLanguage: String
    var translatedLanguage: String
    
    enum CodingKeys: CodingKey {
        case user
        case original
        case translated
        case originalLanguage
        case translatedLanguage
    }
}

@Observable
class ViewModel: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    
    let client = OpenAI(apiToken: "")
    #error("OPENAI KEY GOES HERE")
    
    var audioPlayer: AVAudioPlayer!
    var audioRecorder: AVAudioRecorder!
    #if !os(macOS)
    var recordingSession = AVAudioSession.sharedInstance()
    #endif
    var animationTimer: Timer?
    var recordingTimer: Timer?
    var audioPower = 0.0
    var prevAudioPower: Double?
    var processingSpeechTask: Task<Void, Never>?
    
    var translations: [Translation] = []
    
    var captureURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("recording.m4a")
    }
    
    var state = VoiceChatState.idle {
        didSet { print(state) }
    }
    var isIdle: Bool {
        if case .idle = state {
            return true
        }
        return false
    }
    
    var siriWaveFormOpacity: CGFloat {
        switch state {
        case .recordingSpeech, .playingSpeech: return 1
        default: return 0
        }
    }
    
    override init() {
        super.init()
        #if !os(macOS)
        do {
            #if os(iOS)
            try recordingSession.setCategory(.playAndRecord, options: .defaultToSpeaker)
            #else
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            #endif
            try recordingSession.setActive(true)
            
            AVAudioApplication.requestRecordPermission { [unowned self] allowed in
                if !allowed {
                    self.state = .error("Recording not allowed by the user" as! Error)
                }
            }
        } catch {
            state = .error(error)
        }
        #endif
    }
    
    func startCaptureAudio() {
        resetValues()
        state = .recordingSpeech
        do {
            audioRecorder = try AVAudioRecorder(url: captureURL,
                                                settings: [
                                                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                                                    AVSampleRateKey: 12000,
                                                    AVNumberOfChannelsKey: 1,
                                                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                                                ])
            audioRecorder.isMeteringEnabled = true
            audioRecorder.delegate = self
            audioRecorder.record()
        } catch {
            resetValues()
            state = .error(error)
        }
    }
    
    func finishCaptureAudio(language: String) {
        resetValues()
        do {
            let data = try Data(contentsOf: captureURL)
            processingSpeechTask = processSpeechTask(audioData: data, language: language)
        } catch {
            state = .error(error)
            resetValues()
        }
    }
    
    var json = ""
    
    func processSpeechTask(audioData: Data, language: String) -> Task<Void, Never> {
        Task { @MainActor [unowned self] in
            self.json = ""
            do {
                self.state = .processingSpeech
                let recordings = try await client.audioTranscriptions(query: .init(file: audioData, fileName: "recording.m4a", model: .whisper_1, prompt: language))
                    
                
                print(recordings.text)
                try Task.checkCancellation()
                self.client.chatsStream(query: .init(model: .gpt3_5Turbo, messages: [.init(role: .user, content: """
                        
                        You're role in this is to detect the languages of each message and return them in another. There are at least 2 different people speaking & each of them speak different languages. You don't know the languages at first, but you should detect which is which, and should return both the original and the the translated version in a JSON format. 
                        
                        
                        GOOD EXAMPLE:
                        
                        {user: "1", original: "Hello! How are you?", translated: "Ola! Como voce esta?", originalLanguage: "English", translatedLanguage: "Portuguese"}
                        {user: "2", original: "Oi! Estou tudo tranquilo. Quero jugar?", translated: "Hey! Everything is chill. Wanna play?", originalLanguage: "Portuguese", translatedLanguage: "English"}

                        RULES:
                        YOU MUST ADHERE TO THESE RULES. DO NOT BREAK ANY PATTERNS.
                        DO NOT RETURN THE JSON IN AN ARRAY, RETURN IT EXACTLY HOW I WROTE IT. DO NOT INCLUDE INDENTATIONS OR LINE BREAKS WHEN RETURNING THE JSON.
                        DO NOT RETURN THE ORIGINAL AS IT'S OWN JSON OBJECT, ONLY RETURN THE TRANSLATIONS.
                        THE KEYS SPECIFICIED SHOULD NEVER CHANGE TO ANY OTHER TERM.
                        ONLY RETURN THE JSON

                        Keep the languages separate, nobody is speaking the same language.
                        If someone starts speaking portuguese for example, it should recognize that that is a different user speaking.
                        This should function as if it were a conversation between a couple people (or more) so don't repeat what has already been translated.
                        
                        
                        The default language is \(language).
                        The conversation is: \(recordings.text)
                        """)])) { result in
                    print("response text")
                    switch result {
                    case .success(let result):
                        self.json += result.choices.first?.delta.content ?? ""
                        if let translation = self.parseChatFromJSON(self.json) {
                            withAnimation(.spring) {
                                self.translations.append(translation)
                            }
                        }
                    case.failure(let error):
                        print(error)
                    }
                } completion: { error in
                    print(error)
                }
            } catch {
                if Task.isCancelled { return }
                state = .error(error)
                resetValues()
            }
        }
    }
    
    func parseChatFromJSON(_ json: String) -> Translation? {
        do {
            
            // Assuming json is a valid JSON string, you need to parse it
            let data = json.data(using: .utf8)!
            let decoder = JSONDecoder()
            let chatResult = try decoder.decode(Translation.self, from: data)
            self.json = ""
            // Now extract todos from chatResult
            return chatResult
        } catch {
            print(json)
            print("Error parsing JSON: \(error.localizedDescription)")
            return nil
        }
    }
    
    func cancelRecording() {
        resetValues()
        state = .idle
    }
    
    func cancelProcessingTask() {
        processingSpeechTask?.cancel()
        processingSpeechTask = nil
        resetValues()
        state = .idle
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            resetValues()
            state = .idle
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        resetValues()
        state = .idle
    }
    
    func resetValues() {
        audioPower = 0
        prevAudioPower = nil
        audioRecorder?.stop()
        audioRecorder = nil
        audioPlayer?.stop()
        audioPlayer = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
}

enum VoiceChatState {
    case idle
    case recordingSpeech
    case processingSpeech
    case playingSpeech
    case error(Error)
}
