// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _usernameMeta =
      const VerificationMeta('username');
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
      'username', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('ma_auth'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [username, displayName, source, createdAt, isActive];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(Insertable<Profile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('username')) {
      context.handle(_usernameMeta,
          username.isAcceptableOrUnknown(data['username']!, _usernameMeta));
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {username};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      username: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}username'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name']),
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  /// MA username or manually entered name (primary key)
  final String username;

  /// Display name from MA or same as username
  final String? displayName;

  /// How the profile was created: 'ma_auth' or 'manual'
  final String source;

  /// When the profile was created
  final DateTime createdAt;

  /// Whether this is the currently active profile
  final bool isActive;
  const Profile(
      {required this.username,
      this.displayName,
      required this.source,
      required this.createdAt,
      required this.isActive});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['username'] = Variable<String>(username);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['source'] = Variable<String>(source);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      username: Value(username),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      source: Value(source),
      createdAt: Value(createdAt),
      isActive: Value(isActive),
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      source: serializer.fromJson<String>(json['source']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String?>(displayName),
      'source': serializer.toJson<String>(source),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  Profile copyWith(
          {String? username,
          Value<String?> displayName = const Value.absent(),
          String? source,
          DateTime? createdAt,
          bool? isActive}) =>
      Profile(
        username: username ?? this.username,
        displayName: displayName.present ? displayName.value : this.displayName,
        source: source ?? this.source,
        createdAt: createdAt ?? this.createdAt,
        isActive: isActive ?? this.isActive,
      );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      username: data.username.present ? data.username.value : this.username,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      source: data.source.present ? data.source.value : this.source,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(username, displayName, source, createdAt, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.source == this.source &&
          other.createdAt == this.createdAt &&
          other.isActive == this.isActive);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<String> username;
  final Value<String?> displayName;
  final Value<String> source;
  final Value<DateTime> createdAt;
  final Value<bool> isActive;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String username,
    this.displayName = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : username = Value(username);
  static Insertable<Profile> custom({
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<String>? source,
    Expression<DateTime>? createdAt,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (source != null) 'source': source,
      if (createdAt != null) 'created_at': createdAt,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith(
      {Value<String>? username,
      Value<String?>? displayName,
      Value<String>? source,
      Value<DateTime>? createdAt,
      Value<bool>? isActive,
      Value<int>? rowid}) {
    return ProfilesCompanion(
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentlyPlayedTable extends RecentlyPlayed
    with TableInfo<$RecentlyPlayedTable, RecentlyPlayedData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentlyPlayedTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _profileUsernameMeta =
      const VerificationMeta('profileUsername');
  @override
  late final GeneratedColumn<String> profileUsername = GeneratedColumn<String>(
      'profile_username', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES profiles (username)'));
  static const VerificationMeta _mediaIdMeta =
      const VerificationMeta('mediaId');
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
      'media_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mediaTypeMeta =
      const VerificationMeta('mediaType');
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
      'media_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artistNameMeta =
      const VerificationMeta('artistName');
  @override
  late final GeneratedColumn<String> artistName = GeneratedColumn<String>(
      'artist_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _metadataMeta =
      const VerificationMeta('metadata');
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
      'metadata', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _playedAtMeta =
      const VerificationMeta('playedAt');
  @override
  late final GeneratedColumn<DateTime> playedAt = GeneratedColumn<DateTime>(
      'played_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        profileUsername,
        mediaId,
        mediaType,
        name,
        artistName,
        imageUrl,
        metadata,
        playedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recently_played';
  @override
  VerificationContext validateIntegrity(Insertable<RecentlyPlayedData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('profile_username')) {
      context.handle(
          _profileUsernameMeta,
          profileUsername.isAcceptableOrUnknown(
              data['profile_username']!, _profileUsernameMeta));
    } else if (isInserting) {
      context.missing(_profileUsernameMeta);
    }
    if (data.containsKey('media_id')) {
      context.handle(_mediaIdMeta,
          mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta));
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(_mediaTypeMeta,
          mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta));
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('artist_name')) {
      context.handle(
          _artistNameMeta,
          artistName.isAcceptableOrUnknown(
              data['artist_name']!, _artistNameMeta));
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    if (data.containsKey('metadata')) {
      context.handle(_metadataMeta,
          metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta));
    }
    if (data.containsKey('played_at')) {
      context.handle(_playedAtMeta,
          playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta));
    } else if (isInserting) {
      context.missing(_playedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentlyPlayedData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentlyPlayedData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      profileUsername: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}profile_username'])!,
      mediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_id'])!,
      mediaType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_type'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      artistName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artist_name']),
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url']),
      metadata: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata']),
      playedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}played_at'])!,
    );
  }

  @override
  $RecentlyPlayedTable createAlias(String alias) {
    return $RecentlyPlayedTable(attachedDatabase, alias);
  }
}

class RecentlyPlayedData extends DataClass
    implements Insertable<RecentlyPlayedData> {
  /// Auto-incrementing ID
  final int id;

  /// Profile this belongs to
  final String profileUsername;

  /// Media item ID from Music Assistant
  final String mediaId;

  /// Type: 'track', 'album', 'artist', 'playlist', 'audiobook'
  final String mediaType;

  /// Display name of the item
  final String name;

  /// Artist/author name (for display)
  final String? artistName;

  /// Image URL for the item
  final String? imageUrl;

  /// Additional metadata as JSON (e.g., album name for tracks)
  final String? metadata;

  /// When this was played
  final DateTime playedAt;
  const RecentlyPlayedData(
      {required this.id,
      required this.profileUsername,
      required this.mediaId,
      required this.mediaType,
      required this.name,
      this.artistName,
      this.imageUrl,
      this.metadata,
      required this.playedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['profile_username'] = Variable<String>(profileUsername);
    map['media_id'] = Variable<String>(mediaId);
    map['media_type'] = Variable<String>(mediaType);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || artistName != null) {
      map['artist_name'] = Variable<String>(artistName);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    map['played_at'] = Variable<DateTime>(playedAt);
    return map;
  }

  RecentlyPlayedCompanion toCompanion(bool nullToAbsent) {
    return RecentlyPlayedCompanion(
      id: Value(id),
      profileUsername: Value(profileUsername),
      mediaId: Value(mediaId),
      mediaType: Value(mediaType),
      name: Value(name),
      artistName: artistName == null && nullToAbsent
          ? const Value.absent()
          : Value(artistName),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      metadata: metadata == null && nullToAbsent
          ? const Value.absent()
          : Value(metadata),
      playedAt: Value(playedAt),
    );
  }

  factory RecentlyPlayedData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentlyPlayedData(
      id: serializer.fromJson<int>(json['id']),
      profileUsername: serializer.fromJson<String>(json['profileUsername']),
      mediaId: serializer.fromJson<String>(json['mediaId']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      name: serializer.fromJson<String>(json['name']),
      artistName: serializer.fromJson<String?>(json['artistName']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      metadata: serializer.fromJson<String?>(json['metadata']),
      playedAt: serializer.fromJson<DateTime>(json['playedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'profileUsername': serializer.toJson<String>(profileUsername),
      'mediaId': serializer.toJson<String>(mediaId),
      'mediaType': serializer.toJson<String>(mediaType),
      'name': serializer.toJson<String>(name),
      'artistName': serializer.toJson<String?>(artistName),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'metadata': serializer.toJson<String?>(metadata),
      'playedAt': serializer.toJson<DateTime>(playedAt),
    };
  }

  RecentlyPlayedData copyWith(
          {int? id,
          String? profileUsername,
          String? mediaId,
          String? mediaType,
          String? name,
          Value<String?> artistName = const Value.absent(),
          Value<String?> imageUrl = const Value.absent(),
          Value<String?> metadata = const Value.absent(),
          DateTime? playedAt}) =>
      RecentlyPlayedData(
        id: id ?? this.id,
        profileUsername: profileUsername ?? this.profileUsername,
        mediaId: mediaId ?? this.mediaId,
        mediaType: mediaType ?? this.mediaType,
        name: name ?? this.name,
        artistName: artistName.present ? artistName.value : this.artistName,
        imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
        metadata: metadata.present ? metadata.value : this.metadata,
        playedAt: playedAt ?? this.playedAt,
      );
  RecentlyPlayedData copyWithCompanion(RecentlyPlayedCompanion data) {
    return RecentlyPlayedData(
      id: data.id.present ? data.id.value : this.id,
      profileUsername: data.profileUsername.present
          ? data.profileUsername.value
          : this.profileUsername,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      name: data.name.present ? data.name.value : this.name,
      artistName:
          data.artistName.present ? data.artistName.value : this.artistName,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentlyPlayedData(')
          ..write('id: $id, ')
          ..write('profileUsername: $profileUsername, ')
          ..write('mediaId: $mediaId, ')
          ..write('mediaType: $mediaType, ')
          ..write('name: $name, ')
          ..write('artistName: $artistName, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('metadata: $metadata, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, profileUsername, mediaId, mediaType, name,
      artistName, imageUrl, metadata, playedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentlyPlayedData &&
          other.id == this.id &&
          other.profileUsername == this.profileUsername &&
          other.mediaId == this.mediaId &&
          other.mediaType == this.mediaType &&
          other.name == this.name &&
          other.artistName == this.artistName &&
          other.imageUrl == this.imageUrl &&
          other.metadata == this.metadata &&
          other.playedAt == this.playedAt);
}

class RecentlyPlayedCompanion extends UpdateCompanion<RecentlyPlayedData> {
  final Value<int> id;
  final Value<String> profileUsername;
  final Value<String> mediaId;
  final Value<String> mediaType;
  final Value<String> name;
  final Value<String?> artistName;
  final Value<String?> imageUrl;
  final Value<String?> metadata;
  final Value<DateTime> playedAt;
  const RecentlyPlayedCompanion({
    this.id = const Value.absent(),
    this.profileUsername = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.name = const Value.absent(),
    this.artistName = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.metadata = const Value.absent(),
    this.playedAt = const Value.absent(),
  });
  RecentlyPlayedCompanion.insert({
    this.id = const Value.absent(),
    required String profileUsername,
    required String mediaId,
    required String mediaType,
    required String name,
    this.artistName = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.metadata = const Value.absent(),
    required DateTime playedAt,
  })  : profileUsername = Value(profileUsername),
        mediaId = Value(mediaId),
        mediaType = Value(mediaType),
        name = Value(name),
        playedAt = Value(playedAt);
  static Insertable<RecentlyPlayedData> custom({
    Expression<int>? id,
    Expression<String>? profileUsername,
    Expression<String>? mediaId,
    Expression<String>? mediaType,
    Expression<String>? name,
    Expression<String>? artistName,
    Expression<String>? imageUrl,
    Expression<String>? metadata,
    Expression<DateTime>? playedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileUsername != null) 'profile_username': profileUsername,
      if (mediaId != null) 'media_id': mediaId,
      if (mediaType != null) 'media_type': mediaType,
      if (name != null) 'name': name,
      if (artistName != null) 'artist_name': artistName,
      if (imageUrl != null) 'image_url': imageUrl,
      if (metadata != null) 'metadata': metadata,
      if (playedAt != null) 'played_at': playedAt,
    });
  }

  RecentlyPlayedCompanion copyWith(
      {Value<int>? id,
      Value<String>? profileUsername,
      Value<String>? mediaId,
      Value<String>? mediaType,
      Value<String>? name,
      Value<String?>? artistName,
      Value<String?>? imageUrl,
      Value<String?>? metadata,
      Value<DateTime>? playedAt}) {
    return RecentlyPlayedCompanion(
      id: id ?? this.id,
      profileUsername: profileUsername ?? this.profileUsername,
      mediaId: mediaId ?? this.mediaId,
      mediaType: mediaType ?? this.mediaType,
      name: name ?? this.name,
      artistName: artistName ?? this.artistName,
      imageUrl: imageUrl ?? this.imageUrl,
      metadata: metadata ?? this.metadata,
      playedAt: playedAt ?? this.playedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (profileUsername.present) {
      map['profile_username'] = Variable<String>(profileUsername.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (artistName.present) {
      map['artist_name'] = Variable<String>(artistName.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<DateTime>(playedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentlyPlayedCompanion(')
          ..write('id: $id, ')
          ..write('profileUsername: $profileUsername, ')
          ..write('mediaId: $mediaId, ')
          ..write('mediaType: $mediaType, ')
          ..write('name: $name, ')
          ..write('artistName: $artistName, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('metadata: $metadata, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }
}

class $LibraryCacheTable extends LibraryCache
    with TableInfo<$LibraryCacheTable, LibraryCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta =
      const VerificationMeta('cacheKey');
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
      'cache_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _itemTypeMeta =
      const VerificationMeta('itemType');
  @override
  late final GeneratedColumn<String> itemType = GeneratedColumn<String>(
      'item_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
      'data', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastSyncedMeta =
      const VerificationMeta('lastSynced');
  @override
  late final GeneratedColumn<DateTime> lastSynced = GeneratedColumn<DateTime>(
      'last_synced', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isDeletedMeta =
      const VerificationMeta('isDeleted');
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
      'is_deleted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_deleted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _sourceProvidersMeta =
      const VerificationMeta('sourceProviders');
  @override
  late final GeneratedColumn<String> sourceProviders = GeneratedColumn<String>(
      'source_providers', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  @override
  List<GeneratedColumn> get $columns => [
        cacheKey,
        itemType,
        itemId,
        data,
        lastSynced,
        isDeleted,
        sourceProviders
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_cache';
  @override
  VerificationContext validateIntegrity(Insertable<LibraryCacheData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(_cacheKeyMeta,
          cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta));
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('item_type')) {
      context.handle(_itemTypeMeta,
          itemType.isAcceptableOrUnknown(data['item_type']!, _itemTypeMeta));
    } else if (isInserting) {
      context.missing(_itemTypeMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
          _dataMeta, this.data.isAcceptableOrUnknown(data['data']!, _dataMeta));
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('last_synced')) {
      context.handle(
          _lastSyncedMeta,
          lastSynced.isAcceptableOrUnknown(
              data['last_synced']!, _lastSyncedMeta));
    } else if (isInserting) {
      context.missing(_lastSyncedMeta);
    }
    if (data.containsKey('is_deleted')) {
      context.handle(_isDeletedMeta,
          isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta));
    }
    if (data.containsKey('source_providers')) {
      context.handle(
          _sourceProvidersMeta,
          sourceProviders.isAcceptableOrUnknown(
              data['source_providers']!, _sourceProvidersMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  LibraryCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryCacheData(
      cacheKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cache_key'])!,
      itemType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_type'])!,
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      data: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}data'])!,
      lastSynced: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_synced'])!,
      isDeleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_deleted'])!,
      sourceProviders: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}source_providers'])!,
    );
  }

  @override
  $LibraryCacheTable createAlias(String alias) {
    return $LibraryCacheTable(attachedDatabase, alias);
  }
}

class LibraryCacheData extends DataClass
    implements Insertable<LibraryCacheData> {
  /// Composite key: provider + item_id
  final String cacheKey;

  /// Type: 'album', 'artist', 'track', 'playlist', 'audiobook', 'audiobook_author'
  final String itemType;

  /// The item ID from Music Assistant
  final String itemId;

  /// Serialized item data as JSON
  final String data;

  /// When this was last synced from MA
  final DateTime lastSynced;

  /// Whether this item was deleted on the server
  final bool isDeleted;

  /// Provider instance IDs that provided this item (JSON array)
  /// Used for client-side filtering by source provider
  final String sourceProviders;
  const LibraryCacheData(
      {required this.cacheKey,
      required this.itemType,
      required this.itemId,
      required this.data,
      required this.lastSynced,
      required this.isDeleted,
      required this.sourceProviders});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['item_type'] = Variable<String>(itemType);
    map['item_id'] = Variable<String>(itemId);
    map['data'] = Variable<String>(data);
    map['last_synced'] = Variable<DateTime>(lastSynced);
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['source_providers'] = Variable<String>(sourceProviders);
    return map;
  }

  LibraryCacheCompanion toCompanion(bool nullToAbsent) {
    return LibraryCacheCompanion(
      cacheKey: Value(cacheKey),
      itemType: Value(itemType),
      itemId: Value(itemId),
      data: Value(data),
      lastSynced: Value(lastSynced),
      isDeleted: Value(isDeleted),
      sourceProviders: Value(sourceProviders),
    );
  }

  factory LibraryCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryCacheData(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      itemType: serializer.fromJson<String>(json['itemType']),
      itemId: serializer.fromJson<String>(json['itemId']),
      data: serializer.fromJson<String>(json['data']),
      lastSynced: serializer.fromJson<DateTime>(json['lastSynced']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      sourceProviders: serializer.fromJson<String>(json['sourceProviders']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'itemType': serializer.toJson<String>(itemType),
      'itemId': serializer.toJson<String>(itemId),
      'data': serializer.toJson<String>(data),
      'lastSynced': serializer.toJson<DateTime>(lastSynced),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'sourceProviders': serializer.toJson<String>(sourceProviders),
    };
  }

  LibraryCacheData copyWith(
          {String? cacheKey,
          String? itemType,
          String? itemId,
          String? data,
          DateTime? lastSynced,
          bool? isDeleted,
          String? sourceProviders}) =>
      LibraryCacheData(
        cacheKey: cacheKey ?? this.cacheKey,
        itemType: itemType ?? this.itemType,
        itemId: itemId ?? this.itemId,
        data: data ?? this.data,
        lastSynced: lastSynced ?? this.lastSynced,
        isDeleted: isDeleted ?? this.isDeleted,
        sourceProviders: sourceProviders ?? this.sourceProviders,
      );
  LibraryCacheData copyWithCompanion(LibraryCacheCompanion data) {
    return LibraryCacheData(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      itemType: data.itemType.present ? data.itemType.value : this.itemType,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      data: data.data.present ? data.data.value : this.data,
      lastSynced:
          data.lastSynced.present ? data.lastSynced.value : this.lastSynced,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      sourceProviders: data.sourceProviders.present
          ? data.sourceProviders.value
          : this.sourceProviders,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryCacheData(')
          ..write('cacheKey: $cacheKey, ')
          ..write('itemType: $itemType, ')
          ..write('itemId: $itemId, ')
          ..write('data: $data, ')
          ..write('lastSynced: $lastSynced, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('sourceProviders: $sourceProviders')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      cacheKey, itemType, itemId, data, lastSynced, isDeleted, sourceProviders);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryCacheData &&
          other.cacheKey == this.cacheKey &&
          other.itemType == this.itemType &&
          other.itemId == this.itemId &&
          other.data == this.data &&
          other.lastSynced == this.lastSynced &&
          other.isDeleted == this.isDeleted &&
          other.sourceProviders == this.sourceProviders);
}

class LibraryCacheCompanion extends UpdateCompanion<LibraryCacheData> {
  final Value<String> cacheKey;
  final Value<String> itemType;
  final Value<String> itemId;
  final Value<String> data;
  final Value<DateTime> lastSynced;
  final Value<bool> isDeleted;
  final Value<String> sourceProviders;
  final Value<int> rowid;
  const LibraryCacheCompanion({
    this.cacheKey = const Value.absent(),
    this.itemType = const Value.absent(),
    this.itemId = const Value.absent(),
    this.data = const Value.absent(),
    this.lastSynced = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.sourceProviders = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryCacheCompanion.insert({
    required String cacheKey,
    required String itemType,
    required String itemId,
    required String data,
    required DateTime lastSynced,
    this.isDeleted = const Value.absent(),
    this.sourceProviders = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : cacheKey = Value(cacheKey),
        itemType = Value(itemType),
        itemId = Value(itemId),
        data = Value(data),
        lastSynced = Value(lastSynced);
  static Insertable<LibraryCacheData> custom({
    Expression<String>? cacheKey,
    Expression<String>? itemType,
    Expression<String>? itemId,
    Expression<String>? data,
    Expression<DateTime>? lastSynced,
    Expression<bool>? isDeleted,
    Expression<String>? sourceProviders,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (itemType != null) 'item_type': itemType,
      if (itemId != null) 'item_id': itemId,
      if (data != null) 'data': data,
      if (lastSynced != null) 'last_synced': lastSynced,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (sourceProviders != null) 'source_providers': sourceProviders,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryCacheCompanion copyWith(
      {Value<String>? cacheKey,
      Value<String>? itemType,
      Value<String>? itemId,
      Value<String>? data,
      Value<DateTime>? lastSynced,
      Value<bool>? isDeleted,
      Value<String>? sourceProviders,
      Value<int>? rowid}) {
    return LibraryCacheCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      itemType: itemType ?? this.itemType,
      itemId: itemId ?? this.itemId,
      data: data ?? this.data,
      lastSynced: lastSynced ?? this.lastSynced,
      isDeleted: isDeleted ?? this.isDeleted,
      sourceProviders: sourceProviders ?? this.sourceProviders,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (itemType.present) {
      map['item_type'] = Variable<String>(itemType.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (lastSynced.present) {
      map['last_synced'] = Variable<DateTime>(lastSynced.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (sourceProviders.present) {
      map['source_providers'] = Variable<String>(sourceProviders.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryCacheCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('itemType: $itemType, ')
          ..write('itemId: $itemId, ')
          ..write('data: $data, ')
          ..write('lastSynced: $lastSynced, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('sourceProviders: $sourceProviders, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetadataTable extends SyncMetadata
    with TableInfo<$SyncMetadataTable, SyncMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _syncTypeMeta =
      const VerificationMeta('syncType');
  @override
  late final GeneratedColumn<String> syncType = GeneratedColumn<String>(
      'sync_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastSyncedAtMeta =
      const VerificationMeta('lastSyncedAt');
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
      'last_synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _itemCountMeta =
      const VerificationMeta('itemCount');
  @override
  late final GeneratedColumn<int> itemCount = GeneratedColumn<int>(
      'item_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [syncType, lastSyncedAt, itemCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_metadata';
  @override
  VerificationContext validateIntegrity(Insertable<SyncMetadataData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sync_type')) {
      context.handle(_syncTypeMeta,
          syncType.isAcceptableOrUnknown(data['sync_type']!, _syncTypeMeta));
    } else if (isInserting) {
      context.missing(_syncTypeMeta);
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
          _lastSyncedAtMeta,
          lastSyncedAt.isAcceptableOrUnknown(
              data['last_synced_at']!, _lastSyncedAtMeta));
    } else if (isInserting) {
      context.missing(_lastSyncedAtMeta);
    }
    if (data.containsKey('item_count')) {
      context.handle(_itemCountMeta,
          itemCount.isAcceptableOrUnknown(data['item_count']!, _itemCountMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {syncType};
  @override
  SyncMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetadataData(
      syncType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_type'])!,
      lastSyncedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_synced_at'])!,
      itemCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}item_count'])!,
    );
  }

  @override
  $SyncMetadataTable createAlias(String alias) {
    return $SyncMetadataTable(attachedDatabase, alias);
  }
}

class SyncMetadataData extends DataClass
    implements Insertable<SyncMetadataData> {
  /// What was synced: 'albums', 'artists', 'audiobooks', etc.
  final String syncType;

  /// When the last successful sync completed
  final DateTime lastSyncedAt;

  /// Number of items synced
  final int itemCount;
  const SyncMetadataData(
      {required this.syncType,
      required this.lastSyncedAt,
      required this.itemCount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sync_type'] = Variable<String>(syncType);
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    map['item_count'] = Variable<int>(itemCount);
    return map;
  }

  SyncMetadataCompanion toCompanion(bool nullToAbsent) {
    return SyncMetadataCompanion(
      syncType: Value(syncType),
      lastSyncedAt: Value(lastSyncedAt),
      itemCount: Value(itemCount),
    );
  }

  factory SyncMetadataData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetadataData(
      syncType: serializer.fromJson<String>(json['syncType']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
      itemCount: serializer.fromJson<int>(json['itemCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'syncType': serializer.toJson<String>(syncType),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
      'itemCount': serializer.toJson<int>(itemCount),
    };
  }

  SyncMetadataData copyWith(
          {String? syncType, DateTime? lastSyncedAt, int? itemCount}) =>
      SyncMetadataData(
        syncType: syncType ?? this.syncType,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        itemCount: itemCount ?? this.itemCount,
      );
  SyncMetadataData copyWithCompanion(SyncMetadataCompanion data) {
    return SyncMetadataData(
      syncType: data.syncType.present ? data.syncType.value : this.syncType,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      itemCount: data.itemCount.present ? data.itemCount.value : this.itemCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataData(')
          ..write('syncType: $syncType, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('itemCount: $itemCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(syncType, lastSyncedAt, itemCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetadataData &&
          other.syncType == this.syncType &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.itemCount == this.itemCount);
}

class SyncMetadataCompanion extends UpdateCompanion<SyncMetadataData> {
  final Value<String> syncType;
  final Value<DateTime> lastSyncedAt;
  final Value<int> itemCount;
  final Value<int> rowid;
  const SyncMetadataCompanion({
    this.syncType = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.itemCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetadataCompanion.insert({
    required String syncType,
    required DateTime lastSyncedAt,
    this.itemCount = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : syncType = Value(syncType),
        lastSyncedAt = Value(lastSyncedAt);
  static Insertable<SyncMetadataData> custom({
    Expression<String>? syncType,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? itemCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (syncType != null) 'sync_type': syncType,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (itemCount != null) 'item_count': itemCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetadataCompanion copyWith(
      {Value<String>? syncType,
      Value<DateTime>? lastSyncedAt,
      Value<int>? itemCount,
      Value<int>? rowid}) {
    return SyncMetadataCompanion(
      syncType: syncType ?? this.syncType,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      itemCount: itemCount ?? this.itemCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (syncType.present) {
      map['sync_type'] = Variable<String>(syncType.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (itemCount.present) {
      map['item_count'] = Variable<int>(itemCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataCompanion(')
          ..write('syncType: $syncType, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('itemCount: $itemCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaybackStateTable extends PlaybackState
    with TableInfo<$PlaybackStateTable, PlaybackStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('current'));
  static const VerificationMeta _playerIdMeta =
      const VerificationMeta('playerId');
  @override
  late final GeneratedColumn<String> playerId = GeneratedColumn<String>(
      'player_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _playerNameMeta =
      const VerificationMeta('playerName');
  @override
  late final GeneratedColumn<String> playerName = GeneratedColumn<String>(
      'player_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _currentTrackJsonMeta =
      const VerificationMeta('currentTrackJson');
  @override
  late final GeneratedColumn<String> currentTrackJson = GeneratedColumn<String>(
      'current_track_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _positionSecondsMeta =
      const VerificationMeta('positionSeconds');
  @override
  late final GeneratedColumn<double> positionSeconds = GeneratedColumn<double>(
      'position_seconds', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _isPlayingMeta =
      const VerificationMeta('isPlaying');
  @override
  late final GeneratedColumn<bool> isPlaying = GeneratedColumn<bool>(
      'is_playing', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_playing" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _savedAtMeta =
      const VerificationMeta('savedAt');
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
      'saved_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        playerId,
        playerName,
        currentTrackJson,
        positionSeconds,
        isPlaying,
        savedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_state';
  @override
  VerificationContext validateIntegrity(Insertable<PlaybackStateData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('player_id')) {
      context.handle(_playerIdMeta,
          playerId.isAcceptableOrUnknown(data['player_id']!, _playerIdMeta));
    }
    if (data.containsKey('player_name')) {
      context.handle(
          _playerNameMeta,
          playerName.isAcceptableOrUnknown(
              data['player_name']!, _playerNameMeta));
    }
    if (data.containsKey('current_track_json')) {
      context.handle(
          _currentTrackJsonMeta,
          currentTrackJson.isAcceptableOrUnknown(
              data['current_track_json']!, _currentTrackJsonMeta));
    }
    if (data.containsKey('position_seconds')) {
      context.handle(
          _positionSecondsMeta,
          positionSeconds.isAcceptableOrUnknown(
              data['position_seconds']!, _positionSecondsMeta));
    }
    if (data.containsKey('is_playing')) {
      context.handle(_isPlayingMeta,
          isPlaying.isAcceptableOrUnknown(data['is_playing']!, _isPlayingMeta));
    }
    if (data.containsKey('saved_at')) {
      context.handle(_savedAtMeta,
          savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta));
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaybackStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackStateData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      playerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}player_id']),
      playerName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}player_name']),
      currentTrackJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}current_track_json']),
      positionSeconds: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}position_seconds'])!,
      isPlaying: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_playing'])!,
      savedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}saved_at'])!,
    );
  }

  @override
  $PlaybackStateTable createAlias(String alias) {
    return $PlaybackStateTable(attachedDatabase, alias);
  }
}

class PlaybackStateData extends DataClass
    implements Insertable<PlaybackStateData> {
  /// Always 'current' - single row table
  final String id;

  /// Selected player ID
  final String? playerId;

  /// Selected player name (for display if player unavailable)
  final String? playerName;

  /// Current track as JSON
  final String? currentTrackJson;

  /// Current position in seconds
  final double positionSeconds;

  /// Whether playback was active
  final bool isPlaying;

  /// When this state was saved
  final DateTime savedAt;
  const PlaybackStateData(
      {required this.id,
      this.playerId,
      this.playerName,
      this.currentTrackJson,
      required this.positionSeconds,
      required this.isPlaying,
      required this.savedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || playerId != null) {
      map['player_id'] = Variable<String>(playerId);
    }
    if (!nullToAbsent || playerName != null) {
      map['player_name'] = Variable<String>(playerName);
    }
    if (!nullToAbsent || currentTrackJson != null) {
      map['current_track_json'] = Variable<String>(currentTrackJson);
    }
    map['position_seconds'] = Variable<double>(positionSeconds);
    map['is_playing'] = Variable<bool>(isPlaying);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  PlaybackStateCompanion toCompanion(bool nullToAbsent) {
    return PlaybackStateCompanion(
      id: Value(id),
      playerId: playerId == null && nullToAbsent
          ? const Value.absent()
          : Value(playerId),
      playerName: playerName == null && nullToAbsent
          ? const Value.absent()
          : Value(playerName),
      currentTrackJson: currentTrackJson == null && nullToAbsent
          ? const Value.absent()
          : Value(currentTrackJson),
      positionSeconds: Value(positionSeconds),
      isPlaying: Value(isPlaying),
      savedAt: Value(savedAt),
    );
  }

  factory PlaybackStateData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackStateData(
      id: serializer.fromJson<String>(json['id']),
      playerId: serializer.fromJson<String?>(json['playerId']),
      playerName: serializer.fromJson<String?>(json['playerName']),
      currentTrackJson: serializer.fromJson<String?>(json['currentTrackJson']),
      positionSeconds: serializer.fromJson<double>(json['positionSeconds']),
      isPlaying: serializer.fromJson<bool>(json['isPlaying']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'playerId': serializer.toJson<String?>(playerId),
      'playerName': serializer.toJson<String?>(playerName),
      'currentTrackJson': serializer.toJson<String?>(currentTrackJson),
      'positionSeconds': serializer.toJson<double>(positionSeconds),
      'isPlaying': serializer.toJson<bool>(isPlaying),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  PlaybackStateData copyWith(
          {String? id,
          Value<String?> playerId = const Value.absent(),
          Value<String?> playerName = const Value.absent(),
          Value<String?> currentTrackJson = const Value.absent(),
          double? positionSeconds,
          bool? isPlaying,
          DateTime? savedAt}) =>
      PlaybackStateData(
        id: id ?? this.id,
        playerId: playerId.present ? playerId.value : this.playerId,
        playerName: playerName.present ? playerName.value : this.playerName,
        currentTrackJson: currentTrackJson.present
            ? currentTrackJson.value
            : this.currentTrackJson,
        positionSeconds: positionSeconds ?? this.positionSeconds,
        isPlaying: isPlaying ?? this.isPlaying,
        savedAt: savedAt ?? this.savedAt,
      );
  PlaybackStateData copyWithCompanion(PlaybackStateCompanion data) {
    return PlaybackStateData(
      id: data.id.present ? data.id.value : this.id,
      playerId: data.playerId.present ? data.playerId.value : this.playerId,
      playerName:
          data.playerName.present ? data.playerName.value : this.playerName,
      currentTrackJson: data.currentTrackJson.present
          ? data.currentTrackJson.value
          : this.currentTrackJson,
      positionSeconds: data.positionSeconds.present
          ? data.positionSeconds.value
          : this.positionSeconds,
      isPlaying: data.isPlaying.present ? data.isPlaying.value : this.isPlaying,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackStateData(')
          ..write('id: $id, ')
          ..write('playerId: $playerId, ')
          ..write('playerName: $playerName, ')
          ..write('currentTrackJson: $currentTrackJson, ')
          ..write('positionSeconds: $positionSeconds, ')
          ..write('isPlaying: $isPlaying, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, playerId, playerName, currentTrackJson,
      positionSeconds, isPlaying, savedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackStateData &&
          other.id == this.id &&
          other.playerId == this.playerId &&
          other.playerName == this.playerName &&
          other.currentTrackJson == this.currentTrackJson &&
          other.positionSeconds == this.positionSeconds &&
          other.isPlaying == this.isPlaying &&
          other.savedAt == this.savedAt);
}

class PlaybackStateCompanion extends UpdateCompanion<PlaybackStateData> {
  final Value<String> id;
  final Value<String?> playerId;
  final Value<String?> playerName;
  final Value<String?> currentTrackJson;
  final Value<double> positionSeconds;
  final Value<bool> isPlaying;
  final Value<DateTime> savedAt;
  final Value<int> rowid;
  const PlaybackStateCompanion({
    this.id = const Value.absent(),
    this.playerId = const Value.absent(),
    this.playerName = const Value.absent(),
    this.currentTrackJson = const Value.absent(),
    this.positionSeconds = const Value.absent(),
    this.isPlaying = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaybackStateCompanion.insert({
    this.id = const Value.absent(),
    this.playerId = const Value.absent(),
    this.playerName = const Value.absent(),
    this.currentTrackJson = const Value.absent(),
    this.positionSeconds = const Value.absent(),
    this.isPlaying = const Value.absent(),
    required DateTime savedAt,
    this.rowid = const Value.absent(),
  }) : savedAt = Value(savedAt);
  static Insertable<PlaybackStateData> custom({
    Expression<String>? id,
    Expression<String>? playerId,
    Expression<String>? playerName,
    Expression<String>? currentTrackJson,
    Expression<double>? positionSeconds,
    Expression<bool>? isPlaying,
    Expression<DateTime>? savedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playerId != null) 'player_id': playerId,
      if (playerName != null) 'player_name': playerName,
      if (currentTrackJson != null) 'current_track_json': currentTrackJson,
      if (positionSeconds != null) 'position_seconds': positionSeconds,
      if (isPlaying != null) 'is_playing': isPlaying,
      if (savedAt != null) 'saved_at': savedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaybackStateCompanion copyWith(
      {Value<String>? id,
      Value<String?>? playerId,
      Value<String?>? playerName,
      Value<String?>? currentTrackJson,
      Value<double>? positionSeconds,
      Value<bool>? isPlaying,
      Value<DateTime>? savedAt,
      Value<int>? rowid}) {
    return PlaybackStateCompanion(
      id: id ?? this.id,
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,
      currentTrackJson: currentTrackJson ?? this.currentTrackJson,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      isPlaying: isPlaying ?? this.isPlaying,
      savedAt: savedAt ?? this.savedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (playerId.present) {
      map['player_id'] = Variable<String>(playerId.value);
    }
    if (playerName.present) {
      map['player_name'] = Variable<String>(playerName.value);
    }
    if (currentTrackJson.present) {
      map['current_track_json'] = Variable<String>(currentTrackJson.value);
    }
    if (positionSeconds.present) {
      map['position_seconds'] = Variable<double>(positionSeconds.value);
    }
    if (isPlaying.present) {
      map['is_playing'] = Variable<bool>(isPlaying.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackStateCompanion(')
          ..write('id: $id, ')
          ..write('playerId: $playerId, ')
          ..write('playerName: $playerName, ')
          ..write('currentTrackJson: $currentTrackJson, ')
          ..write('positionSeconds: $positionSeconds, ')
          ..write('isPlaying: $isPlaying, ')
          ..write('savedAt: $savedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPlayersTable extends CachedPlayers
    with TableInfo<$CachedPlayersTable, CachedPlayer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPlayersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playerIdMeta =
      const VerificationMeta('playerId');
  @override
  late final GeneratedColumn<String> playerId = GeneratedColumn<String>(
      'player_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _playerJsonMeta =
      const VerificationMeta('playerJson');
  @override
  late final GeneratedColumn<String> playerJson = GeneratedColumn<String>(
      'player_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _currentTrackJsonMeta =
      const VerificationMeta('currentTrackJson');
  @override
  late final GeneratedColumn<String> currentTrackJson = GeneratedColumn<String>(
      'current_track_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastUpdatedMeta =
      const VerificationMeta('lastUpdated');
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
      'last_updated', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [playerId, playerJson, currentTrackJson, lastUpdated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_players';
  @override
  VerificationContext validateIntegrity(Insertable<CachedPlayer> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('player_id')) {
      context.handle(_playerIdMeta,
          playerId.isAcceptableOrUnknown(data['player_id']!, _playerIdMeta));
    } else if (isInserting) {
      context.missing(_playerIdMeta);
    }
    if (data.containsKey('player_json')) {
      context.handle(
          _playerJsonMeta,
          playerJson.isAcceptableOrUnknown(
              data['player_json']!, _playerJsonMeta));
    } else if (isInserting) {
      context.missing(_playerJsonMeta);
    }
    if (data.containsKey('current_track_json')) {
      context.handle(
          _currentTrackJsonMeta,
          currentTrackJson.isAcceptableOrUnknown(
              data['current_track_json']!, _currentTrackJsonMeta));
    }
    if (data.containsKey('last_updated')) {
      context.handle(
          _lastUpdatedMeta,
          lastUpdated.isAcceptableOrUnknown(
              data['last_updated']!, _lastUpdatedMeta));
    } else if (isInserting) {
      context.missing(_lastUpdatedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playerId};
  @override
  CachedPlayer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPlayer(
      playerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}player_id'])!,
      playerJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}player_json'])!,
      currentTrackJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}current_track_json']),
      lastUpdated: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_updated'])!,
    );
  }

  @override
  $CachedPlayersTable createAlias(String alias) {
    return $CachedPlayersTable(attachedDatabase, alias);
  }
}

class CachedPlayer extends DataClass implements Insertable<CachedPlayer> {
  /// Player ID from Music Assistant
  final String playerId;

  /// Player data as JSON
  final String playerJson;

  /// Current track for this player as JSON (for mini player display)
  final String? currentTrackJson;

  /// When this was last updated
  final DateTime lastUpdated;
  const CachedPlayer(
      {required this.playerId,
      required this.playerJson,
      this.currentTrackJson,
      required this.lastUpdated});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['player_id'] = Variable<String>(playerId);
    map['player_json'] = Variable<String>(playerJson);
    if (!nullToAbsent || currentTrackJson != null) {
      map['current_track_json'] = Variable<String>(currentTrackJson);
    }
    map['last_updated'] = Variable<DateTime>(lastUpdated);
    return map;
  }

  CachedPlayersCompanion toCompanion(bool nullToAbsent) {
    return CachedPlayersCompanion(
      playerId: Value(playerId),
      playerJson: Value(playerJson),
      currentTrackJson: currentTrackJson == null && nullToAbsent
          ? const Value.absent()
          : Value(currentTrackJson),
      lastUpdated: Value(lastUpdated),
    );
  }

  factory CachedPlayer.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPlayer(
      playerId: serializer.fromJson<String>(json['playerId']),
      playerJson: serializer.fromJson<String>(json['playerJson']),
      currentTrackJson: serializer.fromJson<String?>(json['currentTrackJson']),
      lastUpdated: serializer.fromJson<DateTime>(json['lastUpdated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playerId': serializer.toJson<String>(playerId),
      'playerJson': serializer.toJson<String>(playerJson),
      'currentTrackJson': serializer.toJson<String?>(currentTrackJson),
      'lastUpdated': serializer.toJson<DateTime>(lastUpdated),
    };
  }

  CachedPlayer copyWith(
          {String? playerId,
          String? playerJson,
          Value<String?> currentTrackJson = const Value.absent(),
          DateTime? lastUpdated}) =>
      CachedPlayer(
        playerId: playerId ?? this.playerId,
        playerJson: playerJson ?? this.playerJson,
        currentTrackJson: currentTrackJson.present
            ? currentTrackJson.value
            : this.currentTrackJson,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
  CachedPlayer copyWithCompanion(CachedPlayersCompanion data) {
    return CachedPlayer(
      playerId: data.playerId.present ? data.playerId.value : this.playerId,
      playerJson:
          data.playerJson.present ? data.playerJson.value : this.playerJson,
      currentTrackJson: data.currentTrackJson.present
          ? data.currentTrackJson.value
          : this.currentTrackJson,
      lastUpdated:
          data.lastUpdated.present ? data.lastUpdated.value : this.lastUpdated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPlayer(')
          ..write('playerId: $playerId, ')
          ..write('playerJson: $playerJson, ')
          ..write('currentTrackJson: $currentTrackJson, ')
          ..write('lastUpdated: $lastUpdated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(playerId, playerJson, currentTrackJson, lastUpdated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPlayer &&
          other.playerId == this.playerId &&
          other.playerJson == this.playerJson &&
          other.currentTrackJson == this.currentTrackJson &&
          other.lastUpdated == this.lastUpdated);
}

class CachedPlayersCompanion extends UpdateCompanion<CachedPlayer> {
  final Value<String> playerId;
  final Value<String> playerJson;
  final Value<String?> currentTrackJson;
  final Value<DateTime> lastUpdated;
  final Value<int> rowid;
  const CachedPlayersCompanion({
    this.playerId = const Value.absent(),
    this.playerJson = const Value.absent(),
    this.currentTrackJson = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPlayersCompanion.insert({
    required String playerId,
    required String playerJson,
    this.currentTrackJson = const Value.absent(),
    required DateTime lastUpdated,
    this.rowid = const Value.absent(),
  })  : playerId = Value(playerId),
        playerJson = Value(playerJson),
        lastUpdated = Value(lastUpdated);
  static Insertable<CachedPlayer> custom({
    Expression<String>? playerId,
    Expression<String>? playerJson,
    Expression<String>? currentTrackJson,
    Expression<DateTime>? lastUpdated,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playerId != null) 'player_id': playerId,
      if (playerJson != null) 'player_json': playerJson,
      if (currentTrackJson != null) 'current_track_json': currentTrackJson,
      if (lastUpdated != null) 'last_updated': lastUpdated,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPlayersCompanion copyWith(
      {Value<String>? playerId,
      Value<String>? playerJson,
      Value<String?>? currentTrackJson,
      Value<DateTime>? lastUpdated,
      Value<int>? rowid}) {
    return CachedPlayersCompanion(
      playerId: playerId ?? this.playerId,
      playerJson: playerJson ?? this.playerJson,
      currentTrackJson: currentTrackJson ?? this.currentTrackJson,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playerId.present) {
      map['player_id'] = Variable<String>(playerId.value);
    }
    if (playerJson.present) {
      map['player_json'] = Variable<String>(playerJson.value);
    }
    if (currentTrackJson.present) {
      map['current_track_json'] = Variable<String>(currentTrackJson.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPlayersCompanion(')
          ..write('playerId: $playerId, ')
          ..write('playerJson: $playerJson, ')
          ..write('currentTrackJson: $currentTrackJson, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedQueueTable extends CachedQueue
    with TableInfo<$CachedQueueTable, CachedQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _playerIdMeta =
      const VerificationMeta('playerId');
  @override
  late final GeneratedColumn<String> playerId = GeneratedColumn<String>(
      'player_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _itemJsonMeta =
      const VerificationMeta('itemJson');
  @override
  late final GeneratedColumn<String> itemJson = GeneratedColumn<String>(
      'item_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, playerId, itemJson, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_queue';
  @override
  VerificationContext validateIntegrity(Insertable<CachedQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('player_id')) {
      context.handle(_playerIdMeta,
          playerId.isAcceptableOrUnknown(data['player_id']!, _playerIdMeta));
    } else if (isInserting) {
      context.missing(_playerIdMeta);
    }
    if (data.containsKey('item_json')) {
      context.handle(_itemJsonMeta,
          itemJson.isAcceptableOrUnknown(data['item_json']!, _itemJsonMeta));
    } else if (isInserting) {
      context.missing(_itemJsonMeta);
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      playerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}player_id'])!,
      itemJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_json'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
    );
  }

  @override
  $CachedQueueTable createAlias(String alias) {
    return $CachedQueueTable(attachedDatabase, alias);
  }
}

class CachedQueueData extends DataClass implements Insertable<CachedQueueData> {
  /// Auto-incrementing ID for ordering
  final int id;

  /// Player ID this queue belongs to
  final String playerId;

  /// Queue item as JSON
  final String itemJson;

  /// Position in queue
  final int position;
  const CachedQueueData(
      {required this.id,
      required this.playerId,
      required this.itemJson,
      required this.position});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['player_id'] = Variable<String>(playerId);
    map['item_json'] = Variable<String>(itemJson);
    map['position'] = Variable<int>(position);
    return map;
  }

  CachedQueueCompanion toCompanion(bool nullToAbsent) {
    return CachedQueueCompanion(
      id: Value(id),
      playerId: Value(playerId),
      itemJson: Value(itemJson),
      position: Value(position),
    );
  }

  factory CachedQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedQueueData(
      id: serializer.fromJson<int>(json['id']),
      playerId: serializer.fromJson<String>(json['playerId']),
      itemJson: serializer.fromJson<String>(json['itemJson']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playerId': serializer.toJson<String>(playerId),
      'itemJson': serializer.toJson<String>(itemJson),
      'position': serializer.toJson<int>(position),
    };
  }

  CachedQueueData copyWith(
          {int? id, String? playerId, String? itemJson, int? position}) =>
      CachedQueueData(
        id: id ?? this.id,
        playerId: playerId ?? this.playerId,
        itemJson: itemJson ?? this.itemJson,
        position: position ?? this.position,
      );
  CachedQueueData copyWithCompanion(CachedQueueCompanion data) {
    return CachedQueueData(
      id: data.id.present ? data.id.value : this.id,
      playerId: data.playerId.present ? data.playerId.value : this.playerId,
      itemJson: data.itemJson.present ? data.itemJson.value : this.itemJson,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedQueueData(')
          ..write('id: $id, ')
          ..write('playerId: $playerId, ')
          ..write('itemJson: $itemJson, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, playerId, itemJson, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedQueueData &&
          other.id == this.id &&
          other.playerId == this.playerId &&
          other.itemJson == this.itemJson &&
          other.position == this.position);
}

class CachedQueueCompanion extends UpdateCompanion<CachedQueueData> {
  final Value<int> id;
  final Value<String> playerId;
  final Value<String> itemJson;
  final Value<int> position;
  const CachedQueueCompanion({
    this.id = const Value.absent(),
    this.playerId = const Value.absent(),
    this.itemJson = const Value.absent(),
    this.position = const Value.absent(),
  });
  CachedQueueCompanion.insert({
    this.id = const Value.absent(),
    required String playerId,
    required String itemJson,
    required int position,
  })  : playerId = Value(playerId),
        itemJson = Value(itemJson),
        position = Value(position);
  static Insertable<CachedQueueData> custom({
    Expression<int>? id,
    Expression<String>? playerId,
    Expression<String>? itemJson,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playerId != null) 'player_id': playerId,
      if (itemJson != null) 'item_json': itemJson,
      if (position != null) 'position': position,
    });
  }

  CachedQueueCompanion copyWith(
      {Value<int>? id,
      Value<String>? playerId,
      Value<String>? itemJson,
      Value<int>? position}) {
    return CachedQueueCompanion(
      id: id ?? this.id,
      playerId: playerId ?? this.playerId,
      itemJson: itemJson ?? this.itemJson,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playerId.present) {
      map['player_id'] = Variable<String>(playerId.value);
    }
    if (itemJson.present) {
      map['item_json'] = Variable<String>(itemJson.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedQueueCompanion(')
          ..write('id: $id, ')
          ..write('playerId: $playerId, ')
          ..write('itemJson: $itemJson, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $HomeRowCacheTable extends HomeRowCache
    with TableInfo<$HomeRowCacheTable, HomeRowCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HomeRowCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowTypeMeta =
      const VerificationMeta('rowType');
  @override
  late final GeneratedColumn<String> rowType = GeneratedColumn<String>(
      'row_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _itemsJsonMeta =
      const VerificationMeta('itemsJson');
  @override
  late final GeneratedColumn<String> itemsJson = GeneratedColumn<String>(
      'items_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastUpdatedMeta =
      const VerificationMeta('lastUpdated');
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
      'last_updated', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [rowType, itemsJson, lastUpdated];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'home_row_cache';
  @override
  VerificationContext validateIntegrity(Insertable<HomeRowCacheData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_type')) {
      context.handle(_rowTypeMeta,
          rowType.isAcceptableOrUnknown(data['row_type']!, _rowTypeMeta));
    } else if (isInserting) {
      context.missing(_rowTypeMeta);
    }
    if (data.containsKey('items_json')) {
      context.handle(_itemsJsonMeta,
          itemsJson.isAcceptableOrUnknown(data['items_json']!, _itemsJsonMeta));
    } else if (isInserting) {
      context.missing(_itemsJsonMeta);
    }
    if (data.containsKey('last_updated')) {
      context.handle(
          _lastUpdatedMeta,
          lastUpdated.isAcceptableOrUnknown(
              data['last_updated']!, _lastUpdatedMeta));
    } else if (isInserting) {
      context.missing(_lastUpdatedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowType};
  @override
  HomeRowCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HomeRowCacheData(
      rowType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}row_type'])!,
      itemsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}items_json'])!,
      lastUpdated: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_updated'])!,
    );
  }

  @override
  $HomeRowCacheTable createAlias(String alias) {
    return $HomeRowCacheTable(attachedDatabase, alias);
  }
}

class HomeRowCacheData extends DataClass
    implements Insertable<HomeRowCacheData> {
  /// Row type: 'recent_albums', 'discover_artists', 'discover_albums'
  final String rowType;

  /// Serialized list of items as JSON array
  final String itemsJson;

  /// When this was last updated
  final DateTime lastUpdated;
  const HomeRowCacheData(
      {required this.rowType,
      required this.itemsJson,
      required this.lastUpdated});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_type'] = Variable<String>(rowType);
    map['items_json'] = Variable<String>(itemsJson);
    map['last_updated'] = Variable<DateTime>(lastUpdated);
    return map;
  }

  HomeRowCacheCompanion toCompanion(bool nullToAbsent) {
    return HomeRowCacheCompanion(
      rowType: Value(rowType),
      itemsJson: Value(itemsJson),
      lastUpdated: Value(lastUpdated),
    );
  }

  factory HomeRowCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HomeRowCacheData(
      rowType: serializer.fromJson<String>(json['rowType']),
      itemsJson: serializer.fromJson<String>(json['itemsJson']),
      lastUpdated: serializer.fromJson<DateTime>(json['lastUpdated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rowType': serializer.toJson<String>(rowType),
      'itemsJson': serializer.toJson<String>(itemsJson),
      'lastUpdated': serializer.toJson<DateTime>(lastUpdated),
    };
  }

  HomeRowCacheData copyWith(
          {String? rowType, String? itemsJson, DateTime? lastUpdated}) =>
      HomeRowCacheData(
        rowType: rowType ?? this.rowType,
        itemsJson: itemsJson ?? this.itemsJson,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
  HomeRowCacheData copyWithCompanion(HomeRowCacheCompanion data) {
    return HomeRowCacheData(
      rowType: data.rowType.present ? data.rowType.value : this.rowType,
      itemsJson: data.itemsJson.present ? data.itemsJson.value : this.itemsJson,
      lastUpdated:
          data.lastUpdated.present ? data.lastUpdated.value : this.lastUpdated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HomeRowCacheData(')
          ..write('rowType: $rowType, ')
          ..write('itemsJson: $itemsJson, ')
          ..write('lastUpdated: $lastUpdated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(rowType, itemsJson, lastUpdated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HomeRowCacheData &&
          other.rowType == this.rowType &&
          other.itemsJson == this.itemsJson &&
          other.lastUpdated == this.lastUpdated);
}

class HomeRowCacheCompanion extends UpdateCompanion<HomeRowCacheData> {
  final Value<String> rowType;
  final Value<String> itemsJson;
  final Value<DateTime> lastUpdated;
  final Value<int> rowid;
  const HomeRowCacheCompanion({
    this.rowType = const Value.absent(),
    this.itemsJson = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HomeRowCacheCompanion.insert({
    required String rowType,
    required String itemsJson,
    required DateTime lastUpdated,
    this.rowid = const Value.absent(),
  })  : rowType = Value(rowType),
        itemsJson = Value(itemsJson),
        lastUpdated = Value(lastUpdated);
  static Insertable<HomeRowCacheData> custom({
    Expression<String>? rowType,
    Expression<String>? itemsJson,
    Expression<DateTime>? lastUpdated,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (rowType != null) 'row_type': rowType,
      if (itemsJson != null) 'items_json': itemsJson,
      if (lastUpdated != null) 'last_updated': lastUpdated,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HomeRowCacheCompanion copyWith(
      {Value<String>? rowType,
      Value<String>? itemsJson,
      Value<DateTime>? lastUpdated,
      Value<int>? rowid}) {
    return HomeRowCacheCompanion(
      rowType: rowType ?? this.rowType,
      itemsJson: itemsJson ?? this.itemsJson,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowType.present) {
      map['row_type'] = Variable<String>(rowType.value);
    }
    if (itemsJson.present) {
      map['items_json'] = Variable<String>(itemsJson.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HomeRowCacheCompanion(')
          ..write('rowType: $rowType, ')
          ..write('itemsJson: $itemsJson, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SearchHistoryTable extends SearchHistory
    with TableInfo<$SearchHistoryTable, SearchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
      'query', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _searchedAtMeta =
      const VerificationMeta('searchedAt');
  @override
  late final GeneratedColumn<DateTime> searchedAt = GeneratedColumn<DateTime>(
      'searched_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, query, searchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_history';
  @override
  VerificationContext validateIntegrity(Insertable<SearchHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('query')) {
      context.handle(
          _queryMeta, query.isAcceptableOrUnknown(data['query']!, _queryMeta));
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('searched_at')) {
      context.handle(
          _searchedAtMeta,
          searchedAt.isAcceptableOrUnknown(
              data['searched_at']!, _searchedAtMeta));
    } else if (isInserting) {
      context.missing(_searchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SearchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      query: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}query'])!,
      searchedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}searched_at'])!,
    );
  }

  @override
  $SearchHistoryTable createAlias(String alias) {
    return $SearchHistoryTable(attachedDatabase, alias);
  }
}

class SearchHistoryData extends DataClass
    implements Insertable<SearchHistoryData> {
  /// Auto-incrementing ID
  final int id;

  /// The search query
  final String query;

  /// When the search was performed
  final DateTime searchedAt;
  const SearchHistoryData(
      {required this.id, required this.query, required this.searchedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['query'] = Variable<String>(query);
    map['searched_at'] = Variable<DateTime>(searchedAt);
    return map;
  }

  SearchHistoryCompanion toCompanion(bool nullToAbsent) {
    return SearchHistoryCompanion(
      id: Value(id),
      query: Value(query),
      searchedAt: Value(searchedAt),
    );
  }

  factory SearchHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchHistoryData(
      id: serializer.fromJson<int>(json['id']),
      query: serializer.fromJson<String>(json['query']),
      searchedAt: serializer.fromJson<DateTime>(json['searchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'query': serializer.toJson<String>(query),
      'searchedAt': serializer.toJson<DateTime>(searchedAt),
    };
  }

  SearchHistoryData copyWith({int? id, String? query, DateTime? searchedAt}) =>
      SearchHistoryData(
        id: id ?? this.id,
        query: query ?? this.query,
        searchedAt: searchedAt ?? this.searchedAt,
      );
  SearchHistoryData copyWithCompanion(SearchHistoryCompanion data) {
    return SearchHistoryData(
      id: data.id.present ? data.id.value : this.id,
      query: data.query.present ? data.query.value : this.query,
      searchedAt:
          data.searchedAt.present ? data.searchedAt.value : this.searchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryData(')
          ..write('id: $id, ')
          ..write('query: $query, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, query, searchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchHistoryData &&
          other.id == this.id &&
          other.query == this.query &&
          other.searchedAt == this.searchedAt);
}

class SearchHistoryCompanion extends UpdateCompanion<SearchHistoryData> {
  final Value<int> id;
  final Value<String> query;
  final Value<DateTime> searchedAt;
  const SearchHistoryCompanion({
    this.id = const Value.absent(),
    this.query = const Value.absent(),
    this.searchedAt = const Value.absent(),
  });
  SearchHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String query,
    required DateTime searchedAt,
  })  : query = Value(query),
        searchedAt = Value(searchedAt);
  static Insertable<SearchHistoryData> custom({
    Expression<int>? id,
    Expression<String>? query,
    Expression<DateTime>? searchedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (query != null) 'query': query,
      if (searchedAt != null) 'searched_at': searchedAt,
    });
  }

  SearchHistoryCompanion copyWith(
      {Value<int>? id, Value<String>? query, Value<DateTime>? searchedAt}) {
    return SearchHistoryCompanion(
      id: id ?? this.id,
      query: query ?? this.query,
      searchedAt: searchedAt ?? this.searchedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (searchedAt.present) {
      map['searched_at'] = Variable<DateTime>(searchedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SearchHistoryCompanion(')
          ..write('id: $id, ')
          ..write('query: $query, ')
          ..write('searchedAt: $searchedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $RecentlyPlayedTable recentlyPlayed = $RecentlyPlayedTable(this);
  late final $LibraryCacheTable libraryCache = $LibraryCacheTable(this);
  late final $SyncMetadataTable syncMetadata = $SyncMetadataTable(this);
  late final $PlaybackStateTable playbackState = $PlaybackStateTable(this);
  late final $CachedPlayersTable cachedPlayers = $CachedPlayersTable(this);
  late final $CachedQueueTable cachedQueue = $CachedQueueTable(this);
  late final $HomeRowCacheTable homeRowCache = $HomeRowCacheTable(this);
  late final $SearchHistoryTable searchHistory = $SearchHistoryTable(this);
  late final Index idxRecentlyPlayedProfile = Index(
      'idx_recently_played_profile',
      'CREATE INDEX idx_recently_played_profile ON recently_played (profile_username)');
  late final Index idxRecentlyPlayedProfilePlayed = Index(
      'idx_recently_played_profile_played',
      'CREATE INDEX idx_recently_played_profile_played ON recently_played (profile_username, played_at)');
  late final Index idxLibraryCacheType = Index('idx_library_cache_type',
      'CREATE INDEX idx_library_cache_type ON library_cache (item_type)');
  late final Index idxLibraryCacheTypeDeleted = Index(
      'idx_library_cache_type_deleted',
      'CREATE INDEX idx_library_cache_type_deleted ON library_cache (item_type, is_deleted)');
  late final Index idxCachedQueuePlayer = Index('idx_cached_queue_player',
      'CREATE INDEX idx_cached_queue_player ON cached_queue (player_id)');
  late final Index idxCachedQueuePlayerPosition = Index(
      'idx_cached_queue_player_position',
      'CREATE INDEX idx_cached_queue_player_position ON cached_queue (player_id, position)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        profiles,
        recentlyPlayed,
        libraryCache,
        syncMetadata,
        playbackState,
        cachedPlayers,
        cachedQueue,
        homeRowCache,
        searchHistory,
        idxRecentlyPlayedProfile,
        idxRecentlyPlayedProfilePlayed,
        idxLibraryCacheType,
        idxLibraryCacheTypeDeleted,
        idxCachedQueuePlayer,
        idxCachedQueuePlayerPosition
      ];
}

typedef $$ProfilesTableCreateCompanionBuilder = ProfilesCompanion Function({
  required String username,
  Value<String?> displayName,
  Value<String> source,
  Value<DateTime> createdAt,
  Value<bool> isActive,
  Value<int> rowid,
});
typedef $$ProfilesTableUpdateCompanionBuilder = ProfilesCompanion Function({
  Value<String> username,
  Value<String?> displayName,
  Value<String> source,
  Value<DateTime> createdAt,
  Value<bool> isActive,
  Value<int> rowid,
});

final class $$ProfilesTableReferences
    extends BaseReferences<_$AppDatabase, $ProfilesTable, Profile> {
  $$ProfilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RecentlyPlayedTable, List<RecentlyPlayedData>>
      _recentlyPlayedRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.recentlyPlayed,
              aliasName: $_aliasNameGenerator(
                  db.profiles.username, db.recentlyPlayed.profileUsername));

  $$RecentlyPlayedTableProcessedTableManager get recentlyPlayedRefs {
    final manager = $$RecentlyPlayedTableTableManager($_db, $_db.recentlyPlayed)
        .filter((f) => f.profileUsername.username($_item.username));

    final cache = $_typedResult.readTableOrNull(_recentlyPlayedRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  Expression<bool> recentlyPlayedRefs(
      Expression<bool> Function($$RecentlyPlayedTableFilterComposer f) f) {
    final $$RecentlyPlayedTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.username,
        referencedTable: $db.recentlyPlayed,
        getReferencedColumn: (t) => t.profileUsername,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RecentlyPlayedTableFilterComposer(
              $db: $db,
              $table: $db.recentlyPlayed,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  Expression<T> recentlyPlayedRefs<T extends Object>(
      Expression<T> Function($$RecentlyPlayedTableAnnotationComposer a) f) {
    final $$RecentlyPlayedTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.username,
        referencedTable: $db.recentlyPlayed,
        getReferencedColumn: (t) => t.profileUsername,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RecentlyPlayedTableAnnotationComposer(
              $db: $db,
              $table: $db.recentlyPlayed,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProfilesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProfilesTable,
    Profile,
    $$ProfilesTableFilterComposer,
    $$ProfilesTableOrderingComposer,
    $$ProfilesTableAnnotationComposer,
    $$ProfilesTableCreateCompanionBuilder,
    $$ProfilesTableUpdateCompanionBuilder,
    (Profile, $$ProfilesTableReferences),
    Profile,
    PrefetchHooks Function({bool recentlyPlayedRefs})> {
  $$ProfilesTableTableManager(_$AppDatabase db, $ProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> username = const Value.absent(),
            Value<String?> displayName = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProfilesCompanion(
            username: username,
            displayName: displayName,
            source: source,
            createdAt: createdAt,
            isActive: isActive,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String username,
            Value<String?> displayName = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProfilesCompanion.insert(
            username: username,
            displayName: displayName,
            source: source,
            createdAt: createdAt,
            isActive: isActive,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ProfilesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({recentlyPlayedRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (recentlyPlayedRefs) db.recentlyPlayed
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (recentlyPlayedRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$ProfilesTableReferences
                            ._recentlyPlayedRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProfilesTableReferences(db, table, p0)
                                .recentlyPlayedRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems.where(
                                (e) => e.profileUsername == item.username),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProfilesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProfilesTable,
    Profile,
    $$ProfilesTableFilterComposer,
    $$ProfilesTableOrderingComposer,
    $$ProfilesTableAnnotationComposer,
    $$ProfilesTableCreateCompanionBuilder,
    $$ProfilesTableUpdateCompanionBuilder,
    (Profile, $$ProfilesTableReferences),
    Profile,
    PrefetchHooks Function({bool recentlyPlayedRefs})>;
typedef $$RecentlyPlayedTableCreateCompanionBuilder = RecentlyPlayedCompanion
    Function({
  Value<int> id,
  required String profileUsername,
  required String mediaId,
  required String mediaType,
  required String name,
  Value<String?> artistName,
  Value<String?> imageUrl,
  Value<String?> metadata,
  required DateTime playedAt,
});
typedef $$RecentlyPlayedTableUpdateCompanionBuilder = RecentlyPlayedCompanion
    Function({
  Value<int> id,
  Value<String> profileUsername,
  Value<String> mediaId,
  Value<String> mediaType,
  Value<String> name,
  Value<String?> artistName,
  Value<String?> imageUrl,
  Value<String?> metadata,
  Value<DateTime> playedAt,
});

final class $$RecentlyPlayedTableReferences extends BaseReferences<
    _$AppDatabase, $RecentlyPlayedTable, RecentlyPlayedData> {
  $$RecentlyPlayedTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProfilesTable _profileUsernameTable(_$AppDatabase db) =>
      db.profiles.createAlias($_aliasNameGenerator(
          db.recentlyPlayed.profileUsername, db.profiles.username));

  $$ProfilesTableProcessedTableManager get profileUsername {
    final manager = $$ProfilesTableTableManager($_db, $_db.profiles)
        .filter((f) => f.username($_item.profileUsername));
    final item = $_typedResult.readTableOrNull(_profileUsernameTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$RecentlyPlayedTableFilterComposer
    extends Composer<_$AppDatabase, $RecentlyPlayedTable> {
  $$RecentlyPlayedTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaType => $composableBuilder(
      column: $table.mediaType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artistName => $composableBuilder(
      column: $table.artistName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metadata => $composableBuilder(
      column: $table.metadata, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get playedAt => $composableBuilder(
      column: $table.playedAt, builder: (column) => ColumnFilters(column));

  $$ProfilesTableFilterComposer get profileUsername {
    final $$ProfilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileUsername,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.username,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableFilterComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RecentlyPlayedTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentlyPlayedTable> {
  $$RecentlyPlayedTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaType => $composableBuilder(
      column: $table.mediaType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artistName => $composableBuilder(
      column: $table.artistName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metadata => $composableBuilder(
      column: $table.metadata, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get playedAt => $composableBuilder(
      column: $table.playedAt, builder: (column) => ColumnOrderings(column));

  $$ProfilesTableOrderingComposer get profileUsername {
    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileUsername,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.username,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableOrderingComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RecentlyPlayedTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentlyPlayedTable> {
  $$RecentlyPlayedTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get artistName => $composableBuilder(
      column: $table.artistName, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<DateTime> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);

  $$ProfilesTableAnnotationComposer get profileUsername {
    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileUsername,
        referencedTable: $db.profiles,
        getReferencedColumn: (t) => t.username,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProfilesTableAnnotationComposer(
              $db: $db,
              $table: $db.profiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RecentlyPlayedTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RecentlyPlayedTable,
    RecentlyPlayedData,
    $$RecentlyPlayedTableFilterComposer,
    $$RecentlyPlayedTableOrderingComposer,
    $$RecentlyPlayedTableAnnotationComposer,
    $$RecentlyPlayedTableCreateCompanionBuilder,
    $$RecentlyPlayedTableUpdateCompanionBuilder,
    (RecentlyPlayedData, $$RecentlyPlayedTableReferences),
    RecentlyPlayedData,
    PrefetchHooks Function({bool profileUsername})> {
  $$RecentlyPlayedTableTableManager(
      _$AppDatabase db, $RecentlyPlayedTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentlyPlayedTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentlyPlayedTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentlyPlayedTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> profileUsername = const Value.absent(),
            Value<String> mediaId = const Value.absent(),
            Value<String> mediaType = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> artistName = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<String?> metadata = const Value.absent(),
            Value<DateTime> playedAt = const Value.absent(),
          }) =>
              RecentlyPlayedCompanion(
            id: id,
            profileUsername: profileUsername,
            mediaId: mediaId,
            mediaType: mediaType,
            name: name,
            artistName: artistName,
            imageUrl: imageUrl,
            metadata: metadata,
            playedAt: playedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String profileUsername,
            required String mediaId,
            required String mediaType,
            required String name,
            Value<String?> artistName = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<String?> metadata = const Value.absent(),
            required DateTime playedAt,
          }) =>
              RecentlyPlayedCompanion.insert(
            id: id,
            profileUsername: profileUsername,
            mediaId: mediaId,
            mediaType: mediaType,
            name: name,
            artistName: artistName,
            imageUrl: imageUrl,
            metadata: metadata,
            playedAt: playedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$RecentlyPlayedTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({profileUsername = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (profileUsername) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.profileUsername,
                    referencedTable: $$RecentlyPlayedTableReferences
                        ._profileUsernameTable(db),
                    referencedColumn: $$RecentlyPlayedTableReferences
                        ._profileUsernameTable(db)
                        .username,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$RecentlyPlayedTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RecentlyPlayedTable,
    RecentlyPlayedData,
    $$RecentlyPlayedTableFilterComposer,
    $$RecentlyPlayedTableOrderingComposer,
    $$RecentlyPlayedTableAnnotationComposer,
    $$RecentlyPlayedTableCreateCompanionBuilder,
    $$RecentlyPlayedTableUpdateCompanionBuilder,
    (RecentlyPlayedData, $$RecentlyPlayedTableReferences),
    RecentlyPlayedData,
    PrefetchHooks Function({bool profileUsername})>;
typedef $$LibraryCacheTableCreateCompanionBuilder = LibraryCacheCompanion
    Function({
  required String cacheKey,
  required String itemType,
  required String itemId,
  required String data,
  required DateTime lastSynced,
  Value<bool> isDeleted,
  Value<String> sourceProviders,
  Value<int> rowid,
});
typedef $$LibraryCacheTableUpdateCompanionBuilder = LibraryCacheCompanion
    Function({
  Value<String> cacheKey,
  Value<String> itemType,
  Value<String> itemId,
  Value<String> data,
  Value<DateTime> lastSynced,
  Value<bool> isDeleted,
  Value<String> sourceProviders,
  Value<int> rowid,
});

class $$LibraryCacheTableFilterComposer
    extends Composer<_$AppDatabase, $LibraryCacheTable> {
  $$LibraryCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get itemType => $composableBuilder(
      column: $table.itemType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get itemId => $composableBuilder(
      column: $table.itemId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSynced => $composableBuilder(
      column: $table.lastSynced, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceProviders => $composableBuilder(
      column: $table.sourceProviders,
      builder: (column) => ColumnFilters(column));
}

class $$LibraryCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $LibraryCacheTable> {
  $$LibraryCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get itemType => $composableBuilder(
      column: $table.itemType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get itemId => $composableBuilder(
      column: $table.itemId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get data => $composableBuilder(
      column: $table.data, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSynced => $composableBuilder(
      column: $table.lastSynced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceProviders => $composableBuilder(
      column: $table.sourceProviders,
      builder: (column) => ColumnOrderings(column));
}

class $$LibraryCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $LibraryCacheTable> {
  $$LibraryCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get itemType =>
      $composableBuilder(column: $table.itemType, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSynced => $composableBuilder(
      column: $table.lastSynced, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<String> get sourceProviders => $composableBuilder(
      column: $table.sourceProviders, builder: (column) => column);
}

class $$LibraryCacheTableTableManager extends RootTableManager<
    _$AppDatabase,
    $LibraryCacheTable,
    LibraryCacheData,
    $$LibraryCacheTableFilterComposer,
    $$LibraryCacheTableOrderingComposer,
    $$LibraryCacheTableAnnotationComposer,
    $$LibraryCacheTableCreateCompanionBuilder,
    $$LibraryCacheTableUpdateCompanionBuilder,
    (
      LibraryCacheData,
      BaseReferences<_$AppDatabase, $LibraryCacheTable, LibraryCacheData>
    ),
    LibraryCacheData,
    PrefetchHooks Function()> {
  $$LibraryCacheTableTableManager(_$AppDatabase db, $LibraryCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> cacheKey = const Value.absent(),
            Value<String> itemType = const Value.absent(),
            Value<String> itemId = const Value.absent(),
            Value<String> data = const Value.absent(),
            Value<DateTime> lastSynced = const Value.absent(),
            Value<bool> isDeleted = const Value.absent(),
            Value<String> sourceProviders = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryCacheCompanion(
            cacheKey: cacheKey,
            itemType: itemType,
            itemId: itemId,
            data: data,
            lastSynced: lastSynced,
            isDeleted: isDeleted,
            sourceProviders: sourceProviders,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String cacheKey,
            required String itemType,
            required String itemId,
            required String data,
            required DateTime lastSynced,
            Value<bool> isDeleted = const Value.absent(),
            Value<String> sourceProviders = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryCacheCompanion.insert(
            cacheKey: cacheKey,
            itemType: itemType,
            itemId: itemId,
            data: data,
            lastSynced: lastSynced,
            isDeleted: isDeleted,
            sourceProviders: sourceProviders,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LibraryCacheTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $LibraryCacheTable,
    LibraryCacheData,
    $$LibraryCacheTableFilterComposer,
    $$LibraryCacheTableOrderingComposer,
    $$LibraryCacheTableAnnotationComposer,
    $$LibraryCacheTableCreateCompanionBuilder,
    $$LibraryCacheTableUpdateCompanionBuilder,
    (
      LibraryCacheData,
      BaseReferences<_$AppDatabase, $LibraryCacheTable, LibraryCacheData>
    ),
    LibraryCacheData,
    PrefetchHooks Function()>;
typedef $$SyncMetadataTableCreateCompanionBuilder = SyncMetadataCompanion
    Function({
  required String syncType,
  required DateTime lastSyncedAt,
  Value<int> itemCount,
  Value<int> rowid,
});
typedef $$SyncMetadataTableUpdateCompanionBuilder = SyncMetadataCompanion
    Function({
  Value<String> syncType,
  Value<DateTime> lastSyncedAt,
  Value<int> itemCount,
  Value<int> rowid,
});

class $$SyncMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get syncType => $composableBuilder(
      column: $table.syncType, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get itemCount => $composableBuilder(
      column: $table.itemCount, builder: (column) => ColumnFilters(column));
}

class $$SyncMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get syncType => $composableBuilder(
      column: $table.syncType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get itemCount => $composableBuilder(
      column: $table.itemCount, builder: (column) => ColumnOrderings(column));
}

class $$SyncMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get syncType =>
      $composableBuilder(column: $table.syncType, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
      column: $table.lastSyncedAt, builder: (column) => column);

  GeneratedColumn<int> get itemCount =>
      $composableBuilder(column: $table.itemCount, builder: (column) => column);
}

class $$SyncMetadataTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncMetadataTable,
    SyncMetadataData,
    $$SyncMetadataTableFilterComposer,
    $$SyncMetadataTableOrderingComposer,
    $$SyncMetadataTableAnnotationComposer,
    $$SyncMetadataTableCreateCompanionBuilder,
    $$SyncMetadataTableUpdateCompanionBuilder,
    (
      SyncMetadataData,
      BaseReferences<_$AppDatabase, $SyncMetadataTable, SyncMetadataData>
    ),
    SyncMetadataData,
    PrefetchHooks Function()> {
  $$SyncMetadataTableTableManager(_$AppDatabase db, $SyncMetadataTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> syncType = const Value.absent(),
            Value<DateTime> lastSyncedAt = const Value.absent(),
            Value<int> itemCount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetadataCompanion(
            syncType: syncType,
            lastSyncedAt: lastSyncedAt,
            itemCount: itemCount,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String syncType,
            required DateTime lastSyncedAt,
            Value<int> itemCount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncMetadataCompanion.insert(
            syncType: syncType,
            lastSyncedAt: lastSyncedAt,
            itemCount: itemCount,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncMetadataTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncMetadataTable,
    SyncMetadataData,
    $$SyncMetadataTableFilterComposer,
    $$SyncMetadataTableOrderingComposer,
    $$SyncMetadataTableAnnotationComposer,
    $$SyncMetadataTableCreateCompanionBuilder,
    $$SyncMetadataTableUpdateCompanionBuilder,
    (
      SyncMetadataData,
      BaseReferences<_$AppDatabase, $SyncMetadataTable, SyncMetadataData>
    ),
    SyncMetadataData,
    PrefetchHooks Function()>;
typedef $$PlaybackStateTableCreateCompanionBuilder = PlaybackStateCompanion
    Function({
  Value<String> id,
  Value<String?> playerId,
  Value<String?> playerName,
  Value<String?> currentTrackJson,
  Value<double> positionSeconds,
  Value<bool> isPlaying,
  required DateTime savedAt,
  Value<int> rowid,
});
typedef $$PlaybackStateTableUpdateCompanionBuilder = PlaybackStateCompanion
    Function({
  Value<String> id,
  Value<String?> playerId,
  Value<String?> playerName,
  Value<String?> currentTrackJson,
  Value<double> positionSeconds,
  Value<bool> isPlaying,
  Value<DateTime> savedAt,
  Value<int> rowid,
});

class $$PlaybackStateTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackStateTable> {
  $$PlaybackStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get playerId => $composableBuilder(
      column: $table.playerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get playerName => $composableBuilder(
      column: $table.playerName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currentTrackJson => $composableBuilder(
      column: $table.currentTrackJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get positionSeconds => $composableBuilder(
      column: $table.positionSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPlaying => $composableBuilder(
      column: $table.isPlaying, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnFilters(column));
}

class $$PlaybackStateTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackStateTable> {
  $$PlaybackStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get playerId => $composableBuilder(
      column: $table.playerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get playerName => $composableBuilder(
      column: $table.playerName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currentTrackJson => $composableBuilder(
      column: $table.currentTrackJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get positionSeconds => $composableBuilder(
      column: $table.positionSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPlaying => $composableBuilder(
      column: $table.isPlaying, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnOrderings(column));
}

class $$PlaybackStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackStateTable> {
  $$PlaybackStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get playerId =>
      $composableBuilder(column: $table.playerId, builder: (column) => column);

  GeneratedColumn<String> get playerName => $composableBuilder(
      column: $table.playerName, builder: (column) => column);

  GeneratedColumn<String> get currentTrackJson => $composableBuilder(
      column: $table.currentTrackJson, builder: (column) => column);

  GeneratedColumn<double> get positionSeconds => $composableBuilder(
      column: $table.positionSeconds, builder: (column) => column);

  GeneratedColumn<bool> get isPlaying =>
      $composableBuilder(column: $table.isPlaying, builder: (column) => column);

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $$PlaybackStateTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PlaybackStateTable,
    PlaybackStateData,
    $$PlaybackStateTableFilterComposer,
    $$PlaybackStateTableOrderingComposer,
    $$PlaybackStateTableAnnotationComposer,
    $$PlaybackStateTableCreateCompanionBuilder,
    $$PlaybackStateTableUpdateCompanionBuilder,
    (
      PlaybackStateData,
      BaseReferences<_$AppDatabase, $PlaybackStateTable, PlaybackStateData>
    ),
    PlaybackStateData,
    PrefetchHooks Function()> {
  $$PlaybackStateTableTableManager(_$AppDatabase db, $PlaybackStateTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaybackStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> playerId = const Value.absent(),
            Value<String?> playerName = const Value.absent(),
            Value<String?> currentTrackJson = const Value.absent(),
            Value<double> positionSeconds = const Value.absent(),
            Value<bool> isPlaying = const Value.absent(),
            Value<DateTime> savedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PlaybackStateCompanion(
            id: id,
            playerId: playerId,
            playerName: playerName,
            currentTrackJson: currentTrackJson,
            positionSeconds: positionSeconds,
            isPlaying: isPlaying,
            savedAt: savedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> playerId = const Value.absent(),
            Value<String?> playerName = const Value.absent(),
            Value<String?> currentTrackJson = const Value.absent(),
            Value<double> positionSeconds = const Value.absent(),
            Value<bool> isPlaying = const Value.absent(),
            required DateTime savedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PlaybackStateCompanion.insert(
            id: id,
            playerId: playerId,
            playerName: playerName,
            currentTrackJson: currentTrackJson,
            positionSeconds: positionSeconds,
            isPlaying: isPlaying,
            savedAt: savedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PlaybackStateTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PlaybackStateTable,
    PlaybackStateData,
    $$PlaybackStateTableFilterComposer,
    $$PlaybackStateTableOrderingComposer,
    $$PlaybackStateTableAnnotationComposer,
    $$PlaybackStateTableCreateCompanionBuilder,
    $$PlaybackStateTableUpdateCompanionBuilder,
    (
      PlaybackStateData,
      BaseReferences<_$AppDatabase, $PlaybackStateTable, PlaybackStateData>
    ),
    PlaybackStateData,
    PrefetchHooks Function()>;
typedef $$CachedPlayersTableCreateCompanionBuilder = CachedPlayersCompanion
    Function({
  required String playerId,
  required String playerJson,
  Value<String?> currentTrackJson,
  required DateTime lastUpdated,
  Value<int> rowid,
});
typedef $$CachedPlayersTableUpdateCompanionBuilder = CachedPlayersCompanion
    Function({
  Value<String> playerId,
  Value<String> playerJson,
  Value<String?> currentTrackJson,
  Value<DateTime> lastUpdated,
  Value<int> rowid,
});

class $$CachedPlayersTableFilterComposer
    extends Composer<_$AppDatabase, $CachedPlayersTable> {
  $$CachedPlayersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playerId => $composableBuilder(
      column: $table.playerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get playerJson => $composableBuilder(
      column: $table.playerJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get currentTrackJson => $composableBuilder(
      column: $table.currentTrackJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => ColumnFilters(column));
}

class $$CachedPlayersTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedPlayersTable> {
  $$CachedPlayersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playerId => $composableBuilder(
      column: $table.playerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get playerJson => $composableBuilder(
      column: $table.playerJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get currentTrackJson => $composableBuilder(
      column: $table.currentTrackJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => ColumnOrderings(column));
}

class $$CachedPlayersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedPlayersTable> {
  $$CachedPlayersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playerId =>
      $composableBuilder(column: $table.playerId, builder: (column) => column);

  GeneratedColumn<String> get playerJson => $composableBuilder(
      column: $table.playerJson, builder: (column) => column);

  GeneratedColumn<String> get currentTrackJson => $composableBuilder(
      column: $table.currentTrackJson, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => column);
}

class $$CachedPlayersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedPlayersTable,
    CachedPlayer,
    $$CachedPlayersTableFilterComposer,
    $$CachedPlayersTableOrderingComposer,
    $$CachedPlayersTableAnnotationComposer,
    $$CachedPlayersTableCreateCompanionBuilder,
    $$CachedPlayersTableUpdateCompanionBuilder,
    (
      CachedPlayer,
      BaseReferences<_$AppDatabase, $CachedPlayersTable, CachedPlayer>
    ),
    CachedPlayer,
    PrefetchHooks Function()> {
  $$CachedPlayersTableTableManager(_$AppDatabase db, $CachedPlayersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPlayersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPlayersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedPlayersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> playerId = const Value.absent(),
            Value<String> playerJson = const Value.absent(),
            Value<String?> currentTrackJson = const Value.absent(),
            Value<DateTime> lastUpdated = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedPlayersCompanion(
            playerId: playerId,
            playerJson: playerJson,
            currentTrackJson: currentTrackJson,
            lastUpdated: lastUpdated,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String playerId,
            required String playerJson,
            Value<String?> currentTrackJson = const Value.absent(),
            required DateTime lastUpdated,
            Value<int> rowid = const Value.absent(),
          }) =>
              CachedPlayersCompanion.insert(
            playerId: playerId,
            playerJson: playerJson,
            currentTrackJson: currentTrackJson,
            lastUpdated: lastUpdated,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedPlayersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedPlayersTable,
    CachedPlayer,
    $$CachedPlayersTableFilterComposer,
    $$CachedPlayersTableOrderingComposer,
    $$CachedPlayersTableAnnotationComposer,
    $$CachedPlayersTableCreateCompanionBuilder,
    $$CachedPlayersTableUpdateCompanionBuilder,
    (
      CachedPlayer,
      BaseReferences<_$AppDatabase, $CachedPlayersTable, CachedPlayer>
    ),
    CachedPlayer,
    PrefetchHooks Function()>;
typedef $$CachedQueueTableCreateCompanionBuilder = CachedQueueCompanion
    Function({
  Value<int> id,
  required String playerId,
  required String itemJson,
  required int position,
});
typedef $$CachedQueueTableUpdateCompanionBuilder = CachedQueueCompanion
    Function({
  Value<int> id,
  Value<String> playerId,
  Value<String> itemJson,
  Value<int> position,
});

class $$CachedQueueTableFilterComposer
    extends Composer<_$AppDatabase, $CachedQueueTable> {
  $$CachedQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get playerId => $composableBuilder(
      column: $table.playerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get itemJson => $composableBuilder(
      column: $table.itemJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));
}

class $$CachedQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedQueueTable> {
  $$CachedQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get playerId => $composableBuilder(
      column: $table.playerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get itemJson => $composableBuilder(
      column: $table.itemJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));
}

class $$CachedQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedQueueTable> {
  $$CachedQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get playerId =>
      $composableBuilder(column: $table.playerId, builder: (column) => column);

  GeneratedColumn<String> get itemJson =>
      $composableBuilder(column: $table.itemJson, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$CachedQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CachedQueueTable,
    CachedQueueData,
    $$CachedQueueTableFilterComposer,
    $$CachedQueueTableOrderingComposer,
    $$CachedQueueTableAnnotationComposer,
    $$CachedQueueTableCreateCompanionBuilder,
    $$CachedQueueTableUpdateCompanionBuilder,
    (
      CachedQueueData,
      BaseReferences<_$AppDatabase, $CachedQueueTable, CachedQueueData>
    ),
    CachedQueueData,
    PrefetchHooks Function()> {
  $$CachedQueueTableTableManager(_$AppDatabase db, $CachedQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> playerId = const Value.absent(),
            Value<String> itemJson = const Value.absent(),
            Value<int> position = const Value.absent(),
          }) =>
              CachedQueueCompanion(
            id: id,
            playerId: playerId,
            itemJson: itemJson,
            position: position,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String playerId,
            required String itemJson,
            required int position,
          }) =>
              CachedQueueCompanion.insert(
            id: id,
            playerId: playerId,
            itemJson: itemJson,
            position: position,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CachedQueueTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CachedQueueTable,
    CachedQueueData,
    $$CachedQueueTableFilterComposer,
    $$CachedQueueTableOrderingComposer,
    $$CachedQueueTableAnnotationComposer,
    $$CachedQueueTableCreateCompanionBuilder,
    $$CachedQueueTableUpdateCompanionBuilder,
    (
      CachedQueueData,
      BaseReferences<_$AppDatabase, $CachedQueueTable, CachedQueueData>
    ),
    CachedQueueData,
    PrefetchHooks Function()>;
typedef $$HomeRowCacheTableCreateCompanionBuilder = HomeRowCacheCompanion
    Function({
  required String rowType,
  required String itemsJson,
  required DateTime lastUpdated,
  Value<int> rowid,
});
typedef $$HomeRowCacheTableUpdateCompanionBuilder = HomeRowCacheCompanion
    Function({
  Value<String> rowType,
  Value<String> itemsJson,
  Value<DateTime> lastUpdated,
  Value<int> rowid,
});

class $$HomeRowCacheTableFilterComposer
    extends Composer<_$AppDatabase, $HomeRowCacheTable> {
  $$HomeRowCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get rowType => $composableBuilder(
      column: $table.rowType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get itemsJson => $composableBuilder(
      column: $table.itemsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => ColumnFilters(column));
}

class $$HomeRowCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $HomeRowCacheTable> {
  $$HomeRowCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get rowType => $composableBuilder(
      column: $table.rowType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get itemsJson => $composableBuilder(
      column: $table.itemsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => ColumnOrderings(column));
}

class $$HomeRowCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $HomeRowCacheTable> {
  $$HomeRowCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get rowType =>
      $composableBuilder(column: $table.rowType, builder: (column) => column);

  GeneratedColumn<String> get itemsJson =>
      $composableBuilder(column: $table.itemsJson, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => column);
}

class $$HomeRowCacheTableTableManager extends RootTableManager<
    _$AppDatabase,
    $HomeRowCacheTable,
    HomeRowCacheData,
    $$HomeRowCacheTableFilterComposer,
    $$HomeRowCacheTableOrderingComposer,
    $$HomeRowCacheTableAnnotationComposer,
    $$HomeRowCacheTableCreateCompanionBuilder,
    $$HomeRowCacheTableUpdateCompanionBuilder,
    (
      HomeRowCacheData,
      BaseReferences<_$AppDatabase, $HomeRowCacheTable, HomeRowCacheData>
    ),
    HomeRowCacheData,
    PrefetchHooks Function()> {
  $$HomeRowCacheTableTableManager(_$AppDatabase db, $HomeRowCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HomeRowCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HomeRowCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HomeRowCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> rowType = const Value.absent(),
            Value<String> itemsJson = const Value.absent(),
            Value<DateTime> lastUpdated = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              HomeRowCacheCompanion(
            rowType: rowType,
            itemsJson: itemsJson,
            lastUpdated: lastUpdated,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String rowType,
            required String itemsJson,
            required DateTime lastUpdated,
            Value<int> rowid = const Value.absent(),
          }) =>
              HomeRowCacheCompanion.insert(
            rowType: rowType,
            itemsJson: itemsJson,
            lastUpdated: lastUpdated,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$HomeRowCacheTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $HomeRowCacheTable,
    HomeRowCacheData,
    $$HomeRowCacheTableFilterComposer,
    $$HomeRowCacheTableOrderingComposer,
    $$HomeRowCacheTableAnnotationComposer,
    $$HomeRowCacheTableCreateCompanionBuilder,
    $$HomeRowCacheTableUpdateCompanionBuilder,
    (
      HomeRowCacheData,
      BaseReferences<_$AppDatabase, $HomeRowCacheTable, HomeRowCacheData>
    ),
    HomeRowCacheData,
    PrefetchHooks Function()>;
typedef $$SearchHistoryTableCreateCompanionBuilder = SearchHistoryCompanion
    Function({
  Value<int> id,
  required String query,
  required DateTime searchedAt,
});
typedef $$SearchHistoryTableUpdateCompanionBuilder = SearchHistoryCompanion
    Function({
  Value<int> id,
  Value<String> query,
  Value<DateTime> searchedAt,
});

class $$SearchHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get query => $composableBuilder(
      column: $table.query, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => ColumnFilters(column));
}

class $$SearchHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get query => $composableBuilder(
      column: $table.query, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => ColumnOrderings(column));
}

class $$SearchHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchHistoryTable> {
  $$SearchHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<DateTime> get searchedAt => $composableBuilder(
      column: $table.searchedAt, builder: (column) => column);
}

class $$SearchHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SearchHistoryTable,
    SearchHistoryData,
    $$SearchHistoryTableFilterComposer,
    $$SearchHistoryTableOrderingComposer,
    $$SearchHistoryTableAnnotationComposer,
    $$SearchHistoryTableCreateCompanionBuilder,
    $$SearchHistoryTableUpdateCompanionBuilder,
    (
      SearchHistoryData,
      BaseReferences<_$AppDatabase, $SearchHistoryTable, SearchHistoryData>
    ),
    SearchHistoryData,
    PrefetchHooks Function()> {
  $$SearchHistoryTableTableManager(_$AppDatabase db, $SearchHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SearchHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SearchHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SearchHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> query = const Value.absent(),
            Value<DateTime> searchedAt = const Value.absent(),
          }) =>
              SearchHistoryCompanion(
            id: id,
            query: query,
            searchedAt: searchedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String query,
            required DateTime searchedAt,
          }) =>
              SearchHistoryCompanion.insert(
            id: id,
            query: query,
            searchedAt: searchedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SearchHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SearchHistoryTable,
    SearchHistoryData,
    $$SearchHistoryTableFilterComposer,
    $$SearchHistoryTableOrderingComposer,
    $$SearchHistoryTableAnnotationComposer,
    $$SearchHistoryTableCreateCompanionBuilder,
    $$SearchHistoryTableUpdateCompanionBuilder,
    (
      SearchHistoryData,
      BaseReferences<_$AppDatabase, $SearchHistoryTable, SearchHistoryData>
    ),
    SearchHistoryData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$RecentlyPlayedTableTableManager get recentlyPlayed =>
      $$RecentlyPlayedTableTableManager(_db, _db.recentlyPlayed);
  $$LibraryCacheTableTableManager get libraryCache =>
      $$LibraryCacheTableTableManager(_db, _db.libraryCache);
  $$SyncMetadataTableTableManager get syncMetadata =>
      $$SyncMetadataTableTableManager(_db, _db.syncMetadata);
  $$PlaybackStateTableTableManager get playbackState =>
      $$PlaybackStateTableTableManager(_db, _db.playbackState);
  $$CachedPlayersTableTableManager get cachedPlayers =>
      $$CachedPlayersTableTableManager(_db, _db.cachedPlayers);
  $$CachedQueueTableTableManager get cachedQueue =>
      $$CachedQueueTableTableManager(_db, _db.cachedQueue);
  $$HomeRowCacheTableTableManager get homeRowCache =>
      $$HomeRowCacheTableTableManager(_db, _db.homeRowCache);
  $$SearchHistoryTableTableManager get searchHistory =>
      $$SearchHistoryTableTableManager(_db, _db.searchHistory);
}
