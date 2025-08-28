//
//  SettingsView.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 6/11/25.
//
import SwiftUI


enum SettingsElementType
{
    case toggle
    case dropDown
}

struct CapsuleToggleStyle: ToggleStyle {
    var onColor: Color = Color(white: 0.2)
    var offColor: Color = Color(white: 0.2)
    var thumbColor: Color = .white
    var borderColor: Color = .purple

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? onColor : offColor)
                    .opacity(configuration.isOn ? 1 : 0.5)
                    .frame(width: 60, height: 34)
                    .overlay(
                        Capsule()
                            .stroke(borderColor, lineWidth: 2)
                    )

                Circle()
                    .fill(thumbColor)
                    .frame(width: 28, height: 28)
                    .padding(3)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}


struct SettingsElement : View
{
    let title : String
    let description : String
    let type : SettingsElementType
    @Binding var isOn : Bool
    
    private let modes = ["30", "60", "120"]
    @State private var currentMode = "60"
    
    var body : some View
    {
        ZStack
        {
            HStack
            {
                VStack(alignment: .leading, spacing: 4)
                {
                    Text(title)
                        .font(.monospaced(.system(size: 20, weight: .bold))())
                        .padding(.leading, 15)
                        .padding(.top, 20)
                    Text(description)
                        .font(.monospaced(.system(size: 15, weight: .regular))())
                        .padding(.leading, 30)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 20)
                }
               
                Spacer()
                
                if (self.type == SettingsElementType.toggle)
                {
                    Toggle("", isOn: $isOn)
                        .toggleStyle(CapsuleToggleStyle())
                        .scaleEffect(1.2)
                        .labelsHidden()
                        .padding(.horizontal, 20)
                }
                else if (self.type == SettingsElementType.dropDown)
                {
                    Menu
                    {
                        Picker("", selection: $currentMode)
                        {
                            ForEach(modes, id: \.self) { mode in
                                Text(mode)
                            }
                        }
                            .pickerStyle(.menu)
                            .frame(width: 80)
                            .padding(.trailing, 8)
                    } label:
                    {
                        HStack(spacing: 2)
                        {
                            Text(currentMode)
                                .font(.system(size: 15, weight:.regular))
                            Image(systemName: "arrow.down")
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(Color.greyOne)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.gray)
        .foregroundColor(.white)
        .cornerRadius(10)
        .shadow(radius: 20)
        .padding(.horizontal, 10)
    }
}
struct SettingsView : View
{
    @EnvironmentObject var manager : StateManager
    @Binding var isVisible : Bool
    
    var body : some View
    {
        ZStack(alignment: .bottom)
        {
            ZStack(alignment: .top)
            {
                Color.greyOne
                    .ignoresSafeArea(edges: .all)
                
                VStack
                {
                    HStack
                    {
                        Text("Settings:")
                            .font(.monospaced(.system(size: 30, weight: .regular))())
                            .frame(alignment: .leading)
                            .padding(.leading, 20)
                            .padding(.vertical, 20)
                        Spacer()
                    }
                    
                    
                    VStack
                    {
                        VStack(spacing: 16)
                        {
                            SettingsElement(title: "Object Segmentation",
                                            description: "Highlights common items in low light conditions",
                                            type: .toggle,
                                            isOn: $manager.useObjectSegmentation
                            )
                            SettingsElement(title: "Auto-Lidar Activation",
                                            description: "Activates lidar when the camera cannot detect any features",
                                            type: .toggle,
                                            isOn: $manager.lidarActivationUponLimitedFeatures
                            )
                            SettingsElement(title: "Diagnostics Enabled",
                                            description: "Enables diagnostics (nerd mode) to debug performance and model output",
                                            type: .toggle,
                                            isOn: $manager.enabledDiagnostics
                            )
                        }
                        .padding(.horizontal, 3)
                    }
                }
                
               
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Button(action: {
                withAnimation(.easeOut(duration: 0.3))
                {
                    isVisible = false
                }
            })
            {
                HStack
                {
                    Spacer()
                    Image(systemName: "chevron.left")
                        .font(.system(size: 35, weight: .bold))
                        .foregroundColor(.purple)
                        .frame(width: 75, height: 75)
                        .background(Color.gray)
                        .clipShape(Circle())
                        .padding()
                        .shadow(radius: 10)
                }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(x: isVisible ? 0 : -300)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
    }
}

#Preview
{
    @Previewable @StateObject var manager = StateManager()
    @Previewable @State var isVisible = true
    SettingsView(isVisible: $isVisible)
        .environmentObject(manager)
}
