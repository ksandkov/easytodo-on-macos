import SwiftUI

struct CheckBox: View {
    @Binding var isOn: Bool
    var isSubtle = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            if isSubtle {
                ZStack {
                    Circle()
                        .strokeBorder(.secondary, lineWidth: 1.2)
                        .frame(width: 16, height: 16)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.22, green: 0.54, blue: 0.36))
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            } else {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Mark incomplete" : "Mark complete")
    }
}
