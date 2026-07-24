import 'package:explorer_os_mobile/features/radio/models/station_profile.dart';

/// Seed catalog of ExplorerOS radio stations.
///
/// These are STATION CONFIGURATION (editorial identity), not destination
/// content — used as a fallback/first-run catalog when the backend hasn't
/// provided profiles yet. The real catalog is data-driven via
/// `StationProfileRepository` and can scale to hundreds of stations; this seed
/// just guarantees the app has sensible stations offline.
const List<StationProfile> defaultStationProfiles = [
  StationProfile(
    id: 'explorer_radio',
    stationId: 'explorer_radio',
    name: 'Explorer Radio',
    description: 'The flagship ExplorerOS station: music, ranger stories, and '
        'location audio.',
    genre: 'Variety',
    mood: 'Adventurous',
    targetAudience: 'All explorers',
  ),
  StationProfile(
    id: 'country_roads',
    stationId: 'country_roads',
    name: 'Country Roads',
    description: 'Road-trip country for the open highway.',
    genre: 'Country',
    mood: 'Easygoing',
  ),
  StationProfile(
    id: 'classic_rock_trails',
    stationId: 'classic_rock_trails',
    name: 'Classic Rock Trails',
    description: 'Timeless rock for the trail.',
    genre: 'Classic Rock',
    mood: 'Energetic',
  ),
  StationProfile(
    id: 'nature_sounds',
    stationId: 'nature_sounds',
    name: 'Nature Sounds',
    description: 'Ambient soundscapes from the wild.',
    genre: 'Ambient',
    mood: 'Calm',
  ),
  StationProfile(
    id: 'campfire_country',
    stationId: 'campfire_country',
    name: 'Campfire Country',
    description: 'Acoustic tunes for the campsite.',
    genre: 'Folk/Acoustic',
    mood: 'Cozy',
  ),
  StationProfile(
    id: 'adventure_mix',
    stationId: 'adventure_mix',
    name: 'Adventure Mix',
    description: 'Upbeat mix to fuel the journey.',
    genre: 'Pop/Mix',
    mood: 'Upbeat',
  ),
  StationProfile(
    id: 'relaxation',
    stationId: 'relaxation',
    name: 'Relaxation',
    description: 'Wind down after a long hike.',
    genre: 'Chill',
    mood: 'Relaxed',
  ),
  StationProfile(
    id: 'kids_explorer',
    stationId: 'kids_explorer',
    name: 'Kids Explorer',
    description: 'Family-friendly songs and stories.',
    genre: 'Kids',
    mood: 'Playful',
    targetAudience: 'Families',
  ),
  StationProfile(
    id: 'history_channel',
    stationId: 'history_channel',
    name: 'History Channel',
    description: 'Stories from the places you travel through.',
    genre: 'Spoken Word',
    mood: 'Informative',
  ),
  StationProfile(
    id: 'national_parks',
    stationId: 'national_parks',
    name: 'National Parks',
    description: 'Guides and tales from the national parks.',
    genre: 'Spoken Word',
    mood: 'Inspiring',
  ),
  StationProfile(
    id: 'state_parks',
    stationId: 'state_parks',
    name: 'State Parks',
    description: 'Local guides for state parks.',
    genre: 'Spoken Word',
    mood: 'Local',
  ),
  StationProfile(
    id: 'florida_explorer',
    stationId: 'florida_explorer',
    name: 'Florida Explorer',
    description: 'Springs, trails, and stories across Florida.',
    genre: 'Variety',
    mood: 'Sunny',
    targetAudience: 'Florida travelers',
  ),
];
