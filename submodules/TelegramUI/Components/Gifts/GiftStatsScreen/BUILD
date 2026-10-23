load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GiftStatsScreen",
    module_name = "GiftStatsScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/ComponentFlow",
        "//submodules/Components/BundleIconComponent",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/TelegramStringFormatting",
        "//submodules/Markdown",
        "//submodules/GraphCore",
        "//submodules/GraphUI",
        "//submodules/GiftStats",
        "//submodules/TelegramUI/Components/Gifts/GiftCardStyle",
        "//submodules/TelegramUI/Components/Gifts/GiftCraftBackdrop",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/TelegramUI/Components/EdgeEffect",
        "//submodules/AppBundle",
        "//submodules/TelegramUI/Components/AnimationCache",
        "//submodules/TelegramUI/Components/MultiAnimationRenderer",
        "//submodules/TelegramUI/Components/EmojiTextAttachmentView",
        "//submodules/TelegramUI/Components/ButtonComponent",
        "//submodules/TelegramUI/Components/PeerInfo/PeerInfoCoverComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
