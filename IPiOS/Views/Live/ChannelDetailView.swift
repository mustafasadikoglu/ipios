import SwiftUI

/// Tek bir kanalın yayın akışı (EPG) ekranı.
///
/// Listeden bir kanala uzun basıldığında ya da "şimdi / sırada" satırına
/// dokunulduğunda açılır; kullanıcı kanalı oynatmadan önce neyin yayında
/// olduğunu görebilir.
struct ChannelDetailView: View {

    let channel: Channel
    let viewModel: LiveViewModel

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var presenter: PlayerPresenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.gutter) {
                header
                programmeList
            }
            .padding(.vertical, Theme.Metrics.gutter)
        }
        .screenBackground()
        .navigationTitle(channel.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Başlık

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            HStack(spacing: Theme.Metrics.rowSpacing) {
                RemoteImage.channelLogo(channel.imageURL, title: channel.title)

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.title)
                        .font(Theme.Fonts.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

                    if let category = channel.categoryName {
                        Text(category)
                            .font(Theme.Fonts.rowSubtitle)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }

            Button(L.t("kind.live")) {
                presenter.present(.channel(channel))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }

    // MARK: - Programlar

    @ViewBuilder
    private var programmeList: some View {
        let programs = viewModel.programs(for: channel)

        if programs.isEmpty {
            EmptyStateView(
                icon: "calendar.badge.exclamationmark",
                title: L.t("live.guide.title"),
                message: L.t("live.guide.empty")
            )
            .frame(minHeight: 260)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L.t("live.guide.all"))
                    .padding(.bottom, 8)

                ForEach(programs) { program in
                    programmeRow(program)

                    Divider()
                        .overlay(Theme.separator)
                        .padding(.leading, Theme.Metrics.gutter)
                }
            }
        }
    }

    private func programmeRow(_ program: EPGProgram) -> some View {
        HStack(alignment: .top, spacing: Theme.Metrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.timeFormatter.string(from: program.start))
                    .font(Theme.Fonts.numeric)
                    .foregroundStyle(program.isLive ? Theme.accent : Theme.textTertiary)
                Text(Format.timeFormatter.string(from: program.end))
                    .font(Theme.Fonts.numeric)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(program.title)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(program.isPast ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)

                    if program.isLive {
                        BadgeLabel(text: L.t("live.badge.live"), style: .live)
                    }
                }

                if let subtitle = program.subtitle {
                    Text(subtitle)
                        .font(Theme.Fonts.rowSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                if program.isLive {
                    ThinProgressBar(value: program.progress)
                        .frame(maxWidth: 200)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 10)
        .opacity(program.isPast ? 0.5 : 1)
    }
}
