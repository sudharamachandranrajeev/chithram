/// Maps Seerr request/media states (plus optional Radarr/Sonarr activity) onto the
/// app's request status names. Pure function; see README for the table.
///
/// Seerr MediaRequestStatus: 1 pending, 2 approved, 3 declined, 4 failed, 5 completed.
/// Seerr MediaStatus: 1 unknown, 2 pending, 3 processing, 4 partially available,
/// 5 available, 6 blocklisted, 7 deleted.
const statusNames = {
  'none',
  'requested',
  'awaitingApproval',
  'approved',
  'searching',
  'downloading',
  'importing',
  'available',
  'failed',
};

/// What Radarr/Sonarr says about the title (null when unknown or unreachable).
class ArrActivity {
  const ArrActivity({
    this.downloading = false,
    this.importing = false,
    this.searching = false,
  });
  final bool downloading;
  final bool importing;
  final bool searching;
}

String mapStatus({int? requestStatus, int? mediaStatus, ArrActivity? arr}) {
  if (mediaStatus == 5 || mediaStatus == 4) return 'available';
  switch (requestStatus) {
    case 1:
      return 'awaitingApproval';
    case 3:
    case 4:
      return 'failed';
    case 5:
      return 'available';
    case 2:
      if (arr != null) {
        if (arr.importing) return 'importing';
        if (arr.downloading) return 'downloading';
        if (arr.searching) return 'searching';
      }
      return 'approved';
  }
  switch (mediaStatus) {
    case 2:
      return 'requested';
    case 3:
      if (arr != null) {
        if (arr.importing) return 'importing';
        if (arr.downloading) return 'downloading';
        if (arr.searching) return 'searching';
      }
      return 'approved';
    case 6:
      return 'failed';
  }
  return 'none';
}
