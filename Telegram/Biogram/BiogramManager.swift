import Foundation
import UIKit

/// Notifications posted on the main queue when Biogram state changes.
public extension Notification.Name {
    static let biogramStateDidChange = Notification.Name("BiogramStateDidChange")
    static let biogramAccountDidLoad = Notification.Name("BiogramAccountDidLoad")
}

/// Singleton manager for Biogram state. Private/local data stays per Telegram account,
/// while public profile customizations are synchronized by BiogramCloudService.
public final class BiogramManager {
    public static let shared = BiogramManager()

    private let storage: BiogramStorage
    private let bannerIOQueue = DispatchQueue(
        label: "org.biogram.banner.io",
        qos: .utility
    )

    // All cache mutations are delivered on the main queue.
    private var currentAccountId: String = "default"
    private var switchGeneration: UInt64 = 0
    private var loadedAccountId: String?
    // Prevent cloud-downloaded profile changes from triggering an upload back to Cloudflare.
    private var isApplyingCloudProfile: Bool = false

    private var cachedCustomizations: BiogramCustomizations
    private var cachedAliases: [String]
    private var cachedVirtualNumbers: [BiogramVirtualNumber]
    private var cachedCollectibles: [BiogramCollectible]
    private var cachedBanner: BiogramBanner?
    private var cachedBannerImage: UIImage?
    private var cachedProfileCardImage: UIImage?

    /// True after the user changes/removes the banner and until
    /// the application is launched again.
    ///
    /// The new banner is written to disk immediately, but the currently
    /// displayed banner remains unchanged until restart. This avoids
    /// forcing PeerInfo layout to rebuild while the user is still inside
    /// the settings screen.
    private var _bannerRestartRequired: Bool = false

    private init(storageBase: URL? = nil) {
        self.storage = BiogramStorage(baseDirectory: storageBase)
        self.cachedCustomizations = BiogramCustomizations()
        self.cachedAliases = []
        self.cachedVirtualNumbers = []
        self.cachedCollectibles = []
        self.cachedBanner = nil
        self.cachedBannerImage = nil
        self.cachedProfileCardImage = nil
        self._bannerRestartRequired = false
    }

    // MARK: - Account

    /// True when the given account (or current) has finished loading from disk.
    public var isLoaded: Bool {
        return self.loadedAccountId != nil &&
            self.loadedAccountId == self.currentAccountId
    }

    public var activeAccountId: String {
        return self.currentAccountId
    }

    /// True after a banner was changed or removed and until the next
    /// application launch/account reload.
    public var bannerRestartRequired: Bool {
        return self._bannerRestartRequired
    }

    /// Switch the local Biogram state to a Telegram account.
    /// The completion is called on the main queue only after JSON and
    /// banner image are loaded.
    public func switchToAccount(
        accountId: String,
        completion: (() -> Void)? = nil
    ) {
        assert(Thread.isMainThread)

        if accountId == self.loadedAccountId {
            completion?()
            return
        }

        // A new account load starts a new runtime state.
        self._bannerRestartRequired = false

        self.currentAccountId = accountId
        self.switchGeneration &+= 1
        let generation = self.switchGeneration

        self.storage.setCurrentAccountId(accountId)

        self.storage.load(for: accountId) { [weak self] payload in
            guard let self else {
                return
            }

            // Decode the image off the main thread.
            var bannerImage: UIImage?

            if let banner = payload.banner {
                let url = Self.bannersDirectory()
                    .appendingPathComponent(banner.localFilename)

                if let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    bannerImage = image
                }
            }
            var profileCardImage: UIImage?
            if let filename = payload.customizations.profileCardStyle?.imageFilename {
                let url = Self.profileCardsDirectory().appendingPathComponent(filename)
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    profileCardImage = image
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                guard generation == self.switchGeneration,
                      accountId == self.currentAccountId else {
                    return
                }

                self.cachedCustomizations = payload.customizations
                self.cachedAliases = payload.aliases
                self.cachedVirtualNumbers = payload.virtualNumbers
                self.cachedCollectibles = payload.collectibles
                self.cachedBanner = payload.banner
                self.cachedBannerImage = bannerImage
                self.cachedProfileCardImage = profileCardImage

                // The new banner is now the active banner because it has
                // been loaded from disk during application/account startup.
                self._bannerRestartRequired = false

                self.loadedAccountId = accountId

                NotificationCenter.default.post(
                    name: .biogramAccountDidLoad,
                    object: self
                )

                NotificationCenter.default.post(
                    name: .biogramStateDidChange,
                    object: self
                )

                completion?()
            }
        }
    }

    /// Call this as early as possible when AccountContext is ready
    /// (app launch / account switch).
    /// Safe to call repeatedly.
    public func ensureAccountLoaded(
        accountId: String,
        completion: (() -> Void)? = nil
    ) {
        // Keep Ghost Mode settings in sync with the active Biogram account.
        GhostModeSettingsManager.shared.ensureAccountLoaded(accountId: accountId)

        if Thread.isMainThread {
            self.switchToAccount(
                accountId: accountId,
                completion: completion
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.switchToAccount(
                    accountId: accountId,
                    completion: completion
                )
            }
        }
    }

    private func notifyStateChanged() {
        assert(Thread.isMainThread)

        NotificationCenter.default.post(
            name: .biogramStateDidChange,
            object: self
        )

        if !self.isApplyingCloudProfile, self.isLoaded {
            BiogramCloudService.shared.scheduleLocalProfileSync(accountId: self.currentAccountId)
        }
    }

    // MARK: - Read accessors

    public var localPremiumEnabled: Bool {
        return self.cachedCustomizations.localPremiumEnabled
    }

    public func aliases() -> [String] {
        return self.cachedAliases
    }

    public func virtualNumbers() -> [BiogramVirtualNumber] {
        return self.cachedVirtualNumbers
    }

    public func collectibles() -> [BiogramCollectible] {
        return self.cachedCollectibles
    }

    public func banner() -> BiogramBanner? {
        return self.cachedBanner
    }

    public func bannerImage() -> UIImage? {
        return self.cachedBannerImage
    }

    /// Calculates the banner height from the original image aspect ratio.
    ///
    /// There is intentionally NO 80...300 pt clamp here.
    /// Width is fixed by the PeerInfo layout and height follows the
    /// original image aspect ratio.
    public func bannerHeight(forWidth width: CGFloat) -> CGFloat {
        guard let image = self.cachedBannerImage,
              image.size.width > 0.0,
              image.size.height > 0.0 else {
            return 140.0
        }

        let ratio = image.size.height / image.size.width

        return max(
            1.0,
            width * ratio
        )
    }

    public var profileColorEnabled: Bool {
        return self.cachedCustomizations.profileColorEnabled
    }

    public var profileColor: BiogramProfileColor? {
        return self.cachedCustomizations.profileColor
    }

    public var profileCardStyle: BiogramProfileCardStyle {
        return self.cachedCustomizations.profileCardStyle ?? BiogramProfileCardStyle()
    }

    public func profileCardImage() -> UIImage? {
        return self.cachedProfileCardImage
    }


    public func cloudProfilePayload() -> BiogramCloudProfilePayload {
        // Biogram virtual numbers are decorative profile identifiers, not the user's
        // Telegram phone number. Publish every one to Biogram profiles regardless of
        // the legacy isPublic flag or Telegram's phone-number privacy setting.
        let publicNumbers = self.cachedVirtualNumbers.map { item in
            BiogramCloudPublicNumber(
                id: item.id,
                label: item.label,
                number: item.number,
                isPublic: true
            )
        }
        return BiogramCloudProfilePayload(
            profileColorEnabled: self.cachedCustomizations.profileColorEnabled,
            profileColor: self.cachedCustomizations.profileColor,
            cardStyle: self.profileCardStyle,
            aliases: self.cachedAliases,
            publicNumbers: publicNumbers,
            publicEnabled: true
        )
    }

    public func setVirtualNumberPublic(
        id: String,
        isPublic: Bool,
        completion: (() -> Void)? = nil
    ) {
        guard let index = self.cachedVirtualNumbers.firstIndex(where: { $0.id == id }) else {
            completion?()
            return
        }
        self.cachedVirtualNumbers[index].isPublic = isPublic
        self.notifyStateChanged()
        self.storage.replaceVirtualNumbers(self.cachedVirtualNumbers, completion: completion)
    }

    public func applyCloudProfile(
        _ profile: BiogramCloudPublicProfile,
        accountId: String,
        completion: (() -> Void)? = nil
    ) {
        guard self.currentAccountId == accountId, self.isLoaded else {
            completion?()
            return
        }

        self.isApplyingCloudProfile = true

        var customizations = self.cachedCustomizations
        customizations.profileColorEnabled = profile.profileColorEnabled
        customizations.profileColor = profile.profileColor
        customizations.profileCardStyle = BiogramProfileCardStyle(
            paletteName: profile.cardStyle.paletteName,
            material: profile.cardStyle.material,
            imageFilename: self.cachedCustomizations.profileCardStyle?.imageFilename
        )
        self.cachedCustomizations = customizations
        self.cachedAliases = profile.aliases

        if let bannerImage = profile.bannerImage {
            // Persist the cloud banner locally so the owner's profile also survives reinstall/account reload.
            _ = self.saveBannerImage(bannerImage, aspectRatio: "free")
        }

        let serverPublicIds = Set(profile.publicNumbers.map { $0.id })
        var mergedNumbers = self.cachedVirtualNumbers.map { number -> BiogramVirtualNumber in
            var visibleNumber = number
            visibleNumber.isPublic = true
            return visibleNumber
        }
        var mergedNumberIds = Set(mergedNumbers.map { $0.id })

        // Merge any profile numbers from Cloudflare that are not on this device.
        // A local copy with the same id is kept so a recent local edit is not overwritten.
        for number in profile.publicNumbers where !mergedNumberIds.contains(number.id) {
            mergedNumbers.append(
                BiogramVirtualNumber(
                    id: number.id,
                    label: number.label,
                    number: number.number,
                    isPublic: true
                )
            )
            mergedNumberIds.insert(number.id)
        }

        let shouldRepublishNumbers =
            self.cachedVirtualNumbers.contains(where: { $0.isPublic != true })
            || mergedNumberIds != serverPublicIds
        self.cachedVirtualNumbers = mergedNumbers

        self.storage.setCustomizations(customizations)
        self.storage.replaceAliases(profile.aliases)
        self.storage.replaceVirtualNumbers(self.cachedVirtualNumbers)

        NotificationCenter.default.post(name: .biogramStateDidChange, object: self)

        guard let image = profile.cardImage else {
            self.isApplyingCloudProfile = false
            if shouldRepublishNumbers {
                BiogramCloudService.shared.scheduleLocalProfileSync(accountId: accountId)
            }
            completion?()
            return
        }

        self.setProfileCardImage(image) { [weak self] in
            guard let self else { completion?(); return }
            self.isApplyingCloudProfile = false
            if shouldRepublishNumbers {
                BiogramCloudService.shared.scheduleLocalProfileSync(accountId: accountId)
            }
            completion?()
        }
    }

    // MARK: - Mutations
    public func setProfileCardStyle(
        _ style: BiogramProfileCardStyle,
        completion: (() -> Void)? = nil
    ) {
        var custom = self.cachedCustomizations
        var normalized = BiogramProfileCardStyle(
            paletteName: style.paletteName,
            material: style.material,
            imageFilename: custom.profileCardStyle?.imageFilename
        )
        normalized.imageFilename = custom.profileCardStyle?.imageFilename
        custom.profileCardStyle = normalized
        self.cachedCustomizations = custom
        self.notifyStateChanged()
        self.storage.setCustomizations(custom, completion: completion)
    }

    /// RESTORE_INCOMPLETE - file too large for single API write; remaining methods follow in next commit
}
