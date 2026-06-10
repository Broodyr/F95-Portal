# F95Zone API Mappings Documentation

This document contains all discovered mappings for "magic numbers" used in the F95Zone API responses.

## Prefix IDs

Prefixes appear to control both game engines/platforms and game status flags.

### Engine/Platform Prefixes
| Prefix ID | Engine/Platform | Color | Source |
|-----------|----------------|-------|---------|
| 3 | VN | `#d32f2f` | "Balls Out: Nu Vagis" |
| 7 | HTML | `#54812d` | "Cocky Me" |
| 13 | WebGL | `#fe5901` | Both examples |
| 47 | Unity | `#ea5201` | "Balls Out: Nu Vagis" |

### Status Prefixes
| Prefix ID | Status | Background Color | Icon | Source |
|-----------|--------|------------------|------|---------|
| 18 | Completed | `#0b79d1` | ✅ `check_circle` | Original implementation |
| 20 | Onhold | `#c255c3` | ⏸️ `pause_circle` | "Cocky Me" |
| 22 | Abandoned | `#8f561a` | ✖️ `cancel` | "Balls Out: Nu Vagis" |

## Tag IDs

Tags appear to be a secondary/legacy system for categorizing games. Used as fallback when prefix-based engine detection fails.

### Engine Tags (Legacy/Fallback)
| Tag ID | Engine | Color | Status |
|--------|--------|-------|---------|
| 107 | Unity | `#ea5201` | Placeholder mapping |
| 130 | Ren'Py | `#9d46e3` | Placeholder mapping |
| 191 | Others | `#6e9e37` | Default fallback |

*Note: Tag mappings are preliminary and may need refinement as more API data becomes available.*

## Complete Engine Color Scheme

All supported engines with their chosen colors for representation:

| Engine | Hex Color |
|--------|-----------|
| Unity | `#ea5201` |
| Others | `#6e9e37` |
| Ren'Py | `#9d46e3` |
| RPGM | `#228fe6` |
| Tads | `#0b79d1` |
| ADRIFT | `#0b79d1` |
| Unreal Engine | `#1152b7` |
| HTML | `#54812d` |
| Java | `#52a6b0` |
| Flash | `#616161` |
| QSP | `#aa2d77` |
| RAGS | `#c77700` |
| WebGL | `#fe5901` |
| VN | `#d32f2f` |

## API Response Structure

### Game Thread Object
```json
{
  "thread_id": 120463,          // Unique thread identifier
  "title": "Game Title",        // Display name
  "creator": "Developer Name",  // Developer/studio
  "version": "v0.0.7",          // Current version string
  "views": 184425,              // View count (formatted with K/M suffixes)
  "likes": 88,                  // Like count
  "prefixes": [13, 3, 47, 22],  // Engine + Status flags (see tables above)
  "tags": [173, 259, ...],      // Content/genre tags
  "rating": 2.4,                // Average rating (0.0 shows as "-")
  "cover": "https://...",       // Cover image URL (4:1 aspect ratio)
  "screens": ["https://..."],   // Screenshot URLs array
  "date": "2 years",            // Last update time (human readable)
  "watched": false,             // User tracking flag
  "ignored": false,             // User tracking flag
  "new": false,                 // New content flag
  "ts": 1696011720              // Unix timestamp
}
```

## Implementation Notes

### Priority System
1. **Prefixes are checked first** for engine detection (more reliable)
2. **Tags are fallback** if no engine found in prefixes
3. **"Others"** is the final fallback if nothing matches

### Status Priority
Status prefixes are mutually exclusive and checked in this order:
1. `isCompleted` (prefix 18)
2. `isAbandoned` (prefix 22)
3. `isOnhold` (prefix 20)
4. Default to normal status

### Multi-Engine Display
When multiple engine prefixes are found, they are displayed as segmented pills:
- Example: "WebGL | VN | Unity"
- Each segment gets its engine-specific color
- White dividers separate segments
- Proper border radius on ends only

## Data Sources

This documentation is based on analysis of these API responses:

1. **"Balls Out: Nu Vagis"** - Thread ID 120463
   - Prefixes: `[13, 3, 47, 22]` (WebGL, VN, Unity, Abandoned)
   - Demonstrated multi-engine and abandoned status

2. **"Cocky Me"** - Thread ID 220563
   - Prefixes: `[13, 7, 20]` (WebGL, HTML, Onhold)
   - Demonstrated onhold status and HTML engine

3. **Original Implementation**
   - Prefix 18 for completed status
   - Basic tag-to-engine mappings

## Future Considerations

- Monitor API responses for new prefix/tag IDs
- Refine tag mappings as more data becomes available
- Consider adding more engine types as discovered
- Status prefixes may have additional values beyond documented ones
