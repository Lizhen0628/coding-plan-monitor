import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 分享卡片数据

struct ShareAccountItem: Identifiable {
    let id = UUID()
    let name: String
    let shortLabel: String
    let tint: Color
    /// 主角窗口（最紧配额）
    let ringPercentage: Double?
    let ringLabel: String?
    /// 纯余额账号
    let balanceText: String?
}

// MARK: - 分享卡片（ImageRenderer 渲染为 PNG 后分享）

struct UsageShareCard: View {
    let items: [ShareAccountItem]
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coding 额度报告")
                        .font(.title2.weight(.bold))
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "gauge.with.needle")
                    .font(.title)
                    .foregroundStyle(.indigo)
            }

            ForEach(items) { item in
                HStack(spacing: 12) {
                    Text(item.shortLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(item.tint.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(1)
                        if let label = item.ringLabel {
                            Text("\(label)额度")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("账户余额")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 4)

                    if let percentage = item.ringPercentage {
                        QuotaRing(
                            percentage: percentage,
                            tint: StatusColor.forPercentage(percentage),
                            size: 44
                        )
                    } else {
                        Text(item.balanceText ?? "--")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.indigo)
                    }
                }
            }

            HStack {
                Spacer()
                Text("Plan Monitor · 把 Coding 额度装进口袋")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Transferable 包装

struct ShareCardImage: Transferable {
    let pngData: Data
    let previewImage: Image

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.pngData }
    }
}

@MainActor
enum ShareCardRenderer {
    static func render(items: [ShareAccountItem], date: Date) -> ShareCardImage? {
        guard !items.isEmpty else { return nil }
        let renderer = ImageRenderer(content: UsageShareCard(items: items, date: date))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage,
              let data = uiImage.pngData() else { return nil }
        return ShareCardImage(pngData: data, previewImage: Image(uiImage: uiImage))
    }
}
