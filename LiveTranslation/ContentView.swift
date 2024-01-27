//
//  ContentView.swift
//  LiveTranslation
//
//  Created by Jared Davidson on 1/27/24.
//

import SwiftUI

struct TranslationView: View {
    var translation: Translation
    var body: some View {
        VStack(alignment: .leading) {
            Text(translation.translated)
                .font(.title)
                .bold()
                .fontDesign(.rounded)
            Text(translation.original)
                .font(.caption)
            HStack {
                Spacer()
                Text(translation.originalLanguage)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    .background(Color.black)
                    .foregroundColor(Color.white)
                    .clipShape(Capsule())
                Image(systemName: "arrow.right")
                Text(translation.translatedLanguage)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    .background(Color.blue)
                    .foregroundColor(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(15)
        .padding(.horizontal)
    }
}

struct ContentView: View {
    @State var viewModel = ViewModel()
    
    @State var recording: Bool = false
    @State var bounce: Bool = false
    
    @State var selectLanguage: Bool = false
    
    @State var currentLanguage = "English"
    let allLanguages: Set<String> = {
        let identifiers = Set(Locale.availableIdentifiers)
        return Set(identifiers
            .compactMap { Locale(identifier: $0).localizedString(forLanguageCode: $0)?.lowercased() }
            .sorted())
    }()
    
    @FocusState var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack {
                TextField("Language", text: self.$currentLanguage)
                    .font(.title2)
                    .bold()
                    .fontDesign(.rounded)
                    .focused(self.$isFocused)
                    .multilineTextAlignment(.center)
                ZStack {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(self.allLanguages.filter({$0.contains(self.currentLanguage.lowercased())}), id: \.self) {
                                language in
                                Button {
                                    self.currentLanguage = language
                                    withAnimation {
                                        self.isFocused = false
                                    }
                                } label: {
                                    Text(language)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                                        .background(Color.black)
                                        .foregroundStyle(Color.white)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                    .opacity(isFocused ? 1.0 : 0)
                    Text("Default Language")
                        .font(.caption)
                        .opacity(isFocused ? 0 : 0.7)
                }
            }
            .padding(5)
            .frame(width: isFocused ? 300 : 250)
            .background(Color.white)
            .cornerRadius(15)
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                    .fill(Color.clear)
                    .allowsTightening(false)
            }
            .animation(.spring, value: isFocused)
            .zIndex(3.0)

            VStack {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(viewModel.translations) {
                            translation in
                            TranslationView(translation: translation)
                                .transition(.asymmetric(insertion: .slide, removal: .slide))
                        }
                    }
                    .padding(.top, 100)
                }
                .zIndex(1.0)
                Spacer()
                Button(action: {
                    if recording {
                        self.recording = false
                        DispatchQueue.main.async {
                            viewModel.finishCaptureAudio(language: self.currentLanguage)
                        }
                    } else {
                        self.recording = true
                        DispatchQueue.main.async {
                            viewModel.startCaptureAudio()
                        }
                    }
                }, label: {
                    ZStack {
                        Image(systemName: "circle.fill")
                            .resizable()
                            .foregroundStyle(.red)
                    }
                })
                .frame(width: bounce ? 70 : recording ? 60 : 30,
                       height: bounce ? 70 : recording ? 60 : 30)
                .offset(y: recording ? -100 : 0)
                .onChange(of: self.recording, { oldValue, newValue in
                    if recording {
                        withAnimation(Animation.interpolatingSpring(.bouncy(extraBounce: 0.3), initialVelocity: 1.0).repeatForever()) {
                            self.bounce.toggle()
                        }
                    } else {
                        withAnimation(Animation.bouncy) {
                            self.bounce = false
                        }
                    }
                })
                .padding(.bottom, 50)
                .zIndex(2.0)
            }
        }
        .task {
            print(allLanguages)
        }
    }
}


#Preview {
    ContentView()
}
