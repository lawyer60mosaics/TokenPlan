import SwiftUI

struct FeatureSectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChineseHelpText: View {
    let text: String
    var systemImage = "info.circle.fill"
    var tint: Color = .blue

    var body: some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BeginnerStepCard: View {
    let number: Int
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.12))
                Text("\(number)")
                    .font(.headline)
                    .foregroundStyle(.indigo)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(number) 步，\(title)，\(detail)")
    }
}

struct FullWidthActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

struct InlineStatusLabel: View {
    let title: String
    let isSuccess: Bool

    var body: some View {
        Label(title, systemImage: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(isSuccess ? Color.green : Color.orange)
            .accessibilityLabel("状态：\(title)")
    }
}
