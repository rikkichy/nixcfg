# Enabled plugins and their preferences. Runtime state stays in Equicord.
{
  CommandsAPI = {
    enabled = true;
  };
  MessageAccessoriesAPI = {
    enabled = true;
  };
  MessageEventsAPI = {
    enabled = true;
  };
  ServerListAPI = {
    enabled = true;
  };
  UserSettingsAPI = {
    enabled = true;
  };
  BetterSettings = {
    enabled = true;
    disableFade = true;
    organizeMenu = true;
    eagerLoad = true;
  };
  ClearURLs = {
    enabled = true;
  };
  CrashHandler = {
    enabled = true;
  };
  FakeNitro = {
    enabled = true;
    enableStickerBypass = true;
    enableStreamQualityBypass = true;
    enableEmojiBypass = true;
    transformEmojis = true;
    transformStickers = true;
    transformCompoundSentence = false;
  };
  FixImagesQuality = {
    enabled = true;
  };
  FixYoutubeEmbeds = {
    enabled = true;
    youtubeDescription = false;
  };
  ForceOwnerCrown = {
    enabled = true;
  };
  NewGuildSettings = {
    enabled = true;
    guild = true;
    messages = 3;
    everyone = true;
    role = true;
    highlights = true;
    events = true;
    showAllChannels = true;
    mobilePush = true;
    voiceChannels = false;
  };
  NoProfileThemes = {
    enabled = true;
  };
  NoTypingAnimation = {
    enabled = true;
  };
  NoUnblockToJump = {
    enabled = true;
  };
  OpenInApp = {
    enabled = true;
    spotify = true;
    steam = true;
    epic = true;
    tidal = true;
    itunes = true;
    vrcx = true;
    telegram = true;
  };
  PermissionFreeWill = {
    enabled = true;
    lockout = true;
    onboarding = true;
  };
  ValidUser = {
    enabled = true;
  };
  BadgeAPI = {
    enabled = true;
  };
  NoTrack = {
    enabled = true;
    disableAnalytics = true;
  };
  Settings = {
    enabled = true;
    settingsLocation = "aboveNitro";
    includeVencordInfoWhenCopying = true;
  };
  ConcatenatedComponentExtractor = {
    enabled = true;
  };
  ContextMenuAPI = {
    enabled = true;
  };
  NoticesAPI = {
    enabled = true;
  };
  SupportHelper = {
    enabled = true;
  };
  AudioPlayerAPI = {
    enabled = true;
  };
  HeaderBarAPI = {
    enabled = true;
  };
  BlockKrisp = {
    enabled = true;
  };
  BypassPinPrompt = {
    enabled = true;
  };
  NoNitroUpsell = {
    enabled = true;
  };
  NoPushToTalk = {
    enabled = true;
  };
  NoRPC = {
    enabled = true;
  };
  Questify = {
    enabled = true;
    disableSponsoredBanner = true;
    disableRelocationNotices = true;
    disableFriendsListPromo = true;
    disableMembersListPromo = true;
    disableAccountPanelPromo = true;
    disableAccountPanelQuestProgress = true;
    disableOrbsAndQuestsBadges = true;
    autoCompleteQuestTypes = {
      PLAY_ON_DESKTOP = false;
      PLAY_ON_XBOX = false;
      PLAY_ON_PLAYSTATION = false;
      PLAY_ACTIVITY = false;
      WATCH_VIDEO = false;
      WATCH_VIDEO_ON_MOBILE = false;
      ACHIEVEMENT_IN_ACTIVITY = false;
    };
    disableQuestsEverything = false;
    allowChangingDangerousSettings = false;
    questButtonIncludedTypes = {
      "1" = false;
      "2" = false;
      "3" = false;
      "4" = false;
      "5" = false;
      WATCH_VIDEO = false;
      WATCH_VIDEO_ON_MOBILE = false;
      ACHIEVEMENT_IN_ACTIVITY = false;
      ACHIEVEMENT_IN_GAME = false;
      PLAY_ACTIVITY = false;
      PLAY_ON_DESKTOP = false;
      PLAY_ON_DESKTOP_V2 = false;
      STREAM_ON_DESKTOP = false;
      PLAY_ON_PLAYSTATION = false;
      PLAY_ON_XBOX = false;
    };
    questButtonLeftClickAction = "nothing";
    questButtonMiddleClickAction = "nothing";
    questButtonRightClickAction = "nothing";
    questButtonDisplay = "never";
    questButtonIndicator = "none";
    questButtonBadgeColor = 2842239;
    notifyOnQuestComplete = true;
    questCompletedAlertSound = null;
    questCompletedAlertVolume = 100;
    notifyOnNewQuests = true;
    newQuestAlertSound = null;
    newQuestAlertVolume = 100;
    notifyOnNewExcludedQuests = false;
    newExcludedQuestAlertSound = null;
    newExcludedQuestAlertVolume = 100;
    questFetchInterval = 0;
    questTileUnclaimedColor = {
      enabled = false;
      color = 2842239;
    };
    questTileGradient = "hide";
    questTilePreload = true;
    questTileClaimedColor = {
      enabled = false;
      color = 6105983;
    };
    questTileIgnoredColor = {
      enabled = false;
      color = 8334124;
    };
    questTileExpiredColor = {
      enabled = false;
      color = 2368553;
    };
    questOrder = [ "EXPIRED" "CLAIMED" "IGNORED" "UNCLAIMED" ];
    unclaimedSubsort = "Expiring ASC";
    claimedSubsort = "Claimed DESC";
    ignoredSubsort = "Recent DESC";
    expiredSubsort = "Expiring DESC";
    rememberQuestPageSort = true;
    rememberQuestPageFilters = true;
    preventVideoQuestsPausing = false;
    makeMobileVideoQuestsDesktopCompatible = false;
    resumeInterruptedQuests = false;
    completeVideoQuestsQuicker = false;
    autoCompleteQuestsSimultaneously = false;
  };
  EquicordHelper = {
    enabled = true;
    noMirroredCamera = false;
    removeActivitySection = false;
    showYourOwnActivityButtons = false;
    forceRoleIcon = false;
    restoreFileDownloadButton = false;
    noModalAnimation = false;
    disableAdoptTagPrompt = false;
    jsonGateway = false;
    hideVoiceIndicatorForMutedChannels = false;
    noBulletPoints = false;
    accountStandingButton = false;
  };
  ExtraContextMenusAPI = {
    enabled = true;
  };
}
