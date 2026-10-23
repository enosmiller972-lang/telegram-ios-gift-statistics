load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GiftCraftBackdrop",
    module_name = "GiftCraftBackdrop",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/AppBundle",
        "//submodules/LocalMediaResources",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/PeerInfo/PeerInfoCoverComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
