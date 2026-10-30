import 'dart:math' as math;
import 'dart:typed_data';

/// Structure-of-Arrays (SoA) pool for player plasma bolts, overdrive nova rays,
/// and enemy bullet-hell orbs.
///
/// Pre-allocates all [Float32List] and [Uint8List] buffers at construction time
/// so spawning, stepping, and batch rendering allocate 0 heap objects per frame.
class SoaProjectilePool {
  static final Float32List _emptyFloat32 = Float32List(0);

  final int capacity;
  final Float32List x;
  final Float32List y;
  final Float32List vx;
  final Float32List vy;
  final Float32List life;
  final Uint8List active;

  /// `0` = player bolt, `1` = enemy orb, `2` = overdrive nova bolt.
  final Uint8List team;

  final Float32List _playerLineBuffer;
  final Float32List _novaLineBuffer;
  final Float32List _enemyPointBuffer;

  int _cursor = 0;
  int _activeCount = 0;
  int _playerLineFloats = 0;
  int _novaLineFloats = 0;
  int _enemyPointFloats = 0;
  bool _isDisposed = false;

  SoaProjectilePool({this.capacity = 512})
      : x = Float32List(capacity),
        y = Float32List(capacity),
        vx = Float32List(capacity),
        vy = Float32List(capacity),
        life = Float32List(capacity),
        active = Uint8List(capacity),
        team = Uint8List(capacity),
        _playerLineBuffer = Float32List(capacity * 4),
        _novaLineBuffer = Float32List(capacity * 4),
        _enemyPointBuffer = Float32List(capacity * 2);

  bool get isDisposed => _isDisposed;
  int get activeCount => _isDisposed ? 0 : _activeCount;

  /// View of active player bolt line segments (`[x0, y0, x1, y1, ...]`).
  Float32List get playerBoltSegments {
    if (_isDisposed || _playerLineFloats == 0) return _emptyFloat32;
    return Float32List.sublistView(_playerLineBuffer, 0, _playerLineFloats);
  }

  /// View of active overdrive nova bolt line segments (`[x0, y0, x1, y1, ...]`).
  Float32List get novaBoltSegments {
    if (_isDisposed || _novaLineFloats == 0) return _emptyFloat32;
    return Float32List.sublistView(_novaLineBuffer, 0, _novaLineFloats);
  }

  /// View of active enemy bullet coordinates (`[x0, y0, x1, y1, ...]`).
  Float32List get enemyOrbPoints {
    if (_isDisposed || _enemyPointFloats == 0) return _emptyFloat32;
    return Float32List.sublistView(_enemyPointBuffer, 0, _enemyPointFloats);
  }

  /// Spawns a single projectile in O(1) time.
  void spawn({
    required double px,
    required double py,
    required double pvx,
    required double pvy,
    required int teamId,
    double lifespan = 2.2,
  }) {
    if (_isDisposed || capacity <= 0) return;
    final int slot = _cursor;
    _cursor = (slot + 1) % capacity;
    if (active[slot] == 0) {
      active[slot] = 1;
      _activeCount++;
    }
    x[slot] = px;
    y[slot] = py;
    vx[slot] = pvx;
    vy[slot] = pvy;
    life[slot] = lifespan;
    team[slot] = teamId;
  }

  /// Deactivates projectile at [index].
  void killAt(int index) {
    if (_isDisposed || index < 0 || index >= capacity) return;
    if (active[index] != 0) {
      active[index] = 0;
      _activeCount--;
    }
  }

  /// Advances all active projectiles and rebuilds GPU batch buffers in-place.
  void step(double dt, double width, double height) {
    if (_isDisposed) return;
    _playerLineFloats = 0;
    _novaLineFloats = 0;
    _enemyPointFloats = 0;
    if (_activeCount <= 0) return;

    int alive = 0;
    for (int i = 0; i < capacity; i++) {
      if (active[i] != 0 && _stepSingle(i, dt, width, height)) {
        alive++;
        _stageGeometry(i);
      }
    }
    _activeCount = alive;
  }

  bool _stepSingle(int i, double dt, double width, double height) {
    final double nextLife = life[i] - dt;
    if (nextLife <= 0.0) {
      active[i] = 0;
      return false;
    }
    final double nx = x[i] + vx[i] * dt;
    final double ny = y[i] + vy[i] * dt;
    if (_isOutOfArena(nx, ny, width, height)) {
      active[i] = 0;
      return false;
    }
    life[i] = nextLife;
    x[i] = nx;
    y[i] = ny;
    return true;
  }

  bool _isOutOfArena(double px, double py, double width, double height) {
    const double margin = 32.0;
    if (px < -margin || px > width + margin) return true;
    return py < -margin || py > height + margin;
  }

  void _stageGeometry(int i) {
    final int t = team[i];
    final double px = x[i];
    final double py = y[i];
    if (t == 1) {
      final int idx = _enemyPointFloats;
      _enemyPointBuffer[idx] = px;
      _enemyPointBuffer[idx + 1] = py;
      _enemyPointFloats = idx + 2;
      return;
    }
    final double tailX = px - vx[i] * 0.028;
    final double tailY = py - vy[i] * 0.028;
    if (t == 0) {
      final int idx = _playerLineFloats;
      _playerLineBuffer[idx] = tailX;
      _playerLineBuffer[idx + 1] = tailY;
      _playerLineBuffer[idx + 2] = px;
      _playerLineBuffer[idx + 3] = py;
      _playerLineFloats = idx + 4;
    } else {
      final int idx = _novaLineFloats;
      _novaLineBuffer[idx] = tailX;
      _novaLineBuffer[idx + 1] = tailY;
      _novaLineBuffer[idx + 2] = px;
      _novaLineBuffer[idx + 3] = py;
      _novaLineFloats = idx + 4;
    }
  }

  void clear() {
    if (_isDisposed) return;
    active.fillRange(0, capacity, 0);
    _activeCount = 0;
    _playerLineFloats = 0;
    _novaLineFloats = 0;
    _enemyPointFloats = 0;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeCount = 0;
    _playerLineFloats = 0;
    _novaLineFloats = 0;
    _enemyPointFloats = 0;
  }
}

/// Structure-of-Arrays (SoA) pool for geometric enemies and bosses.
class SoaEnemyPool {
  final int capacity;
  final Float32List x;
  final Float32List y;
  final Float32List vx;
  final Float32List vy;
  final Float32List hp;
  final Float32List maxHp;
  final Float32List radius;
  final Float32List spin;
  final Float32List fireTimer;
  final Uint8List active;

  /// `0` = Seeker Drone, `1` = Weaver Shooter, `2` = Boss Dreadnought.
  final Uint8List kind;

  int _cursor = 0;
  int _activeCount = 0;
  bool _isDisposed = false;

  SoaEnemyPool({this.capacity = 96})
      : x = Float32List(capacity),
        y = Float32List(capacity),
        vx = Float32List(capacity),
        vy = Float32List(capacity),
        hp = Float32List(capacity),
        maxHp = Float32List(capacity),
        radius = Float32List(capacity),
        spin = Float32List(capacity),
        fireTimer = Float32List(capacity),
        active = Uint8List(capacity),
        kind = Uint8List(capacity);

  bool get isDisposed => _isDisposed;
  int get activeCount => _isDisposed ? 0 : _activeCount;

  /// Spawns an enemy in the next available slot.
  void spawn({
    required double ex,
    required double ey,
    required int enemyKind,
    required double hitPoints,
    required double bodyRadius,
  }) {
    if (_isDisposed || capacity <= 0) return;
    final int slot = _findSlot();
    if (active[slot] == 0) {
      active[slot] = 1;
      _activeCount++;
    }
    x[slot] = ex;
    y[slot] = ey;
    vx[slot] = 0.0;
    vy[slot] = 0.0;
    hp[slot] = hitPoints;
    maxHp[slot] = hitPoints;
    radius[slot] = bodyRadius;
    spin[slot] = 0.0;
    fireTimer[slot] = 0.6 + (slot % 5) * 0.25;
    kind[slot] = enemyKind;
  }

  int _findSlot() {
    for (int n = 0; n < capacity; n++) {
      final int idx = (_cursor + n) % capacity;
      if (active[idx] == 0) {
        _cursor = (idx + 1) % capacity;
        return idx;
      }
    }
    final int fallback = _cursor;
    _cursor = (fallback + 1) % capacity;
    return fallback;
  }

  /// Applies [damage] to enemy at [index]. Returns `true` if the enemy was destroyed.
  bool applyDamage(int index, double damage) {
    if (_isDisposed || index < 0 || index >= capacity) return false;
    if (active[index] == 0) return false;
    final double remaining = hp[index] - damage;
    if (remaining <= 0.0) {
      active[index] = 0;
      _activeCount--;
      return true;
    }
    hp[index] = remaining;
    return false;
  }

  void clear() {
    if (_isDisposed) return;
    active.fillRange(0, capacity, 0);
    _activeCount = 0;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeCount = 0;
  }
}

/// Structure-of-Arrays (SoA) pool for neon velocity sparks & explosion trails.
///
/// Pre-buckets line segments into 4 neon color channels for 4-draw-call batching.
class SoaSparkPool {
  static const int bucketCount = 4;
  static final Float32List _emptyFloat32 = Float32List(0);

  final int capacity;
  final Float32List x;
  final Float32List y;
  final Float32List vx;
  final Float32List vy;
  final Float32List life;
  final Uint8List active;
  final Uint8List colorBucket;

  late final List<Float32List> _bucketLines;
  final Int32List _bucketFloatCounts = Int32List(bucketCount);
  final math.Random _rng;

  int _cursor = 0;
  int _activeCount = 0;
  bool _isDisposed = false;

  SoaSparkPool({this.capacity = 1800, math.Random? random})
      : x = Float32List(capacity),
        y = Float32List(capacity),
        vx = Float32List(capacity),
        vy = Float32List(capacity),
        life = Float32List(capacity),
        active = Uint8List(capacity),
        colorBucket = Uint8List(capacity),
        _rng = random ?? math.Random(101) {
    _bucketLines = List<Float32List>.generate(
      bucketCount,
      (_) => Float32List(capacity * 4),
      growable: false,
    );
  }

  bool get isDisposed => _isDisposed;
  int get activeCount => _isDisposed ? 0 : _activeCount;

  /// Returns active line segments (`[x0, y0, x1, y1, ...]`) for [bucket].
  Float32List bucketSegments(int bucket) {
    if (_isDisposed || bucket < 0 || bucket >= bucketCount) return _emptyFloat32;
    final int floatCount = _bucketFloatCounts[bucket];
    if (floatCount <= 0) return _emptyFloat32;
    return Float32List.sublistView(_bucketLines[bucket], 0, floatCount);
  }

  /// Emits a radial burst of [count] neon sparks at ([ox], [oy]).
  void emitBurst({
    required double ox,
    required double oy,
    required int count,
    int preferredBucket = -1,
    double maxSpeed = 340.0,
  }) {
    if (_isDisposed || count <= 0 || capacity <= 0) return;
    final int total = count < capacity ? count : capacity;
    for (int n = 0; n < total; n++) {
      final int slot = _cursor;
      _cursor = (slot + 1) % capacity;
      if (active[slot] == 0) {
        active[slot] = 1;
        _activeCount++;
      }
      final double angle = _rng.nextDouble() * math.pi * 2.0;
      final double speed = (0.25 + _rng.nextDouble() * 0.75) * maxSpeed;
      x[slot] = ox;
      y[slot] = oy;
      vx[slot] = math.cos(angle) * speed;
      vy[slot] = math.sin(angle) * speed;
      life[slot] = 0.35 + _rng.nextDouble() * 0.55;
      colorBucket[slot] = preferredBucket >= 0
          ? (preferredBucket % bucketCount)
          : (slot % bucketCount);
    }
  }

  /// Advances spark physics and stages line segments per color bucket.
  void step(double dt) {
    if (_isDisposed) return;
    _bucketFloatCounts.fillRange(0, bucketCount, 0);
    if (_activeCount <= 0) return;

    int alive = 0;
    for (int i = 0; i < capacity; i++) {
      if (active[i] != 0 && _stepSpark(i, dt)) {
        alive++;
      }
    }
    _activeCount = alive;
  }

  bool _stepSpark(int i, double dt) {
    final double nextLife = life[i] - dt;
    if (nextLife <= 0.0) {
      active[i] = 0;
      return false;
    }
    life[i] = nextLife;
    final double svx = vx[i] * 0.96;
    final double svy = vy[i] * 0.96;
    final double nx = x[i] + svx * dt;
    final double ny = y[i] + svy * dt;
    vx[i] = svx;
    vy[i] = svy;
    x[i] = nx;
    y[i] = ny;

    final int b = colorBucket[i];
    final int base = _bucketFloatCounts[b];
    final Float32List segs = _bucketLines[b];
    segs[base] = nx - svx * 0.035;
    segs[base + 1] = ny - svy * 0.035;
    segs[base + 2] = nx;
    segs[base + 3] = ny;
    _bucketFloatCounts[b] = base + 4;
    return true;
  }

  void clear() {
    if (_isDisposed) return;
    active.fillRange(0, capacity, 0);
    _bucketFloatCounts.fillRange(0, bucketCount, 0);
    _activeCount = 0;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeCount = 0;
    _bucketFloatCounts.fillRange(0, bucketCount, 0);
  }
}
