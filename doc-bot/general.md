---
alwaysApply: true
title: "DuckDuckGo Browser Development Overview"
description: "General project overview and development guidelines for DuckDuckGo browser development across iOS and macOS platforms"
keywords: ["Swift", "iOS", "macOS", "MVVM", "SwiftUI", "privacy", "architecture", "dependency injection", "design system"]
---

# DuckDuckGo Browser Development Rules Overview

## 🛑 CRITICAL: STOP IMMEDIATELY WHEN TOLD

**MANDATORY BEHAVIOR**: When user says ANY of:
- "stop"
- "wtf" 
- "u doing wrong"
- "what u doing now"
- "why [doing something]"
- Any variation indicating to stop or questioning current action

**IMMEDIATELY STOP** the current action:
1. Do NOT continue with tool calls
2. Do NOT continue explanations  
3. Do NOT try to "fix" things
4. Just acknowledge briefly and wait for new instructions

## 📝 DOCUMENTATION EDITING RULE

**CRITICAL: When updating coding rules and documentation:**
- **ALWAYS edit markdown files directly using file editing tools**
- **NEVER use MCP tools to create or update documentation**
- **This ensures proper version control and maintains documentation integrity**

## 🔍 DOCUMENTATION LOOKUP PROTOCOL

**MANDATORY: Always follow this exact sequence when looking for documentation:**

1. **FIRST**: Call `doc_bot()` for any task - this is non-negotiable
2. **SECOND**: Call `get_document_index()` to see ALL available documents with exact filenames
3. **THIRD**: Use `read_specific_document("exact-filename.md")` with the EXACT filename from the index
4. **NEVER**: Make claims about "documentation says" without actually reading the full document
5. **NEVER**: Use search snippets alone - always read the complete relevant documentation

**Common Mistake Pattern to Avoid:**
```
❌ WRONG: search_documentation() → assume content → make statements
✅ CORRECT: doc_bot() → get_document_index() → read_specific_document() → accurate information
```

**Why This Protocol Exists:**
- Search results show document **titles**, not **filenames**
- Document titles like "Development Commands & Build Instructions" have filenames like `development-commands.md`
- Reading incomplete search snippets leads to wrong conclusions
- The document index shows the exact filenames needed for `read_specific_document()`

## Project Context
This is the DuckDuckGo browser for iOS and macOS, built with privacy-first principles, modern Swift patterns, and cross-platform architecture.

**Key Directories:**
- `iOS/` - iOS browser app (UIKit + SwiftUI hybrid)
- `macOS/` - macOS browser app (AppKit + SwiftUI hybrid) 
- `SharedPackages/` - Cross-platform Swift packages
- `doc-bot/` - Development rules and guidelines

## Architecture Summary
- **Pattern**: MVVM + Coordinators + Dependency Injection
- **UI**: SwiftUI preferred, UIKit/AppKit for legacy
- **Storage**: Core Data + GRDB + Keychain for sensitive data
- **Design**: DesignResourcesKit for colors/icons (MANDATORY)
- **Testing**: >80% coverage required

## Rule Files Reference

### Core Development Rules (Apply to All Code)
- `anti-patterns.md` - What NOT to do (memory leaks, force unwrapping, etc.)
- `code-style.md` - Swift style guide and conventions
- `privacy-security.md` - Privacy requirements (ALWAYS applies)

### Architecture & Patterns
- `architecture.md` - MVVM, DI, and structural patterns
- `property-wrappers.md` - @UserDefaultsWrapper and custom property wrappers
- `feature-flags.md` - Type-safe feature flags and A/B testing

### UI Development
- `swiftui-style.md` - SwiftUI + DesignResourcesKit integration
- `swiftui-advanced.md` - Advanced SwiftUI patterns and techniques
- `webkit-browser.md` - WebView and browser-specific patterns

### Platform-Specific Rules
- `ios-architecture.md` - iOS AppDependencyProvider, MainCoordinator, UIKit patterns
- `macos-window-management.md` - macOS window management and AppKit patterns
- `macos-system-integration.md` - macOS system services and extensions

### Specialized Development
- `testing.md` - Testing patterns and requirements and xcodebuild commands
- `ui-testing.md` - UI testing guidelines and best practices for macOS browser
- `performance-optimization.md` - Performance best practices
- `shared-packages.md` - Cross-platform package development
- `analytics-patterns.md` - Pixel analytics and event tracking

## Quick Start Checklist

### Before Writing Any Code:
1. ✅ Read `privacy-security.md` - Privacy is non-negotiable
2. ✅ Check platform rules (`ios-architecture.md` or `macos-architecture.md`)
3. ✅ Review `anti-patterns.md` - Avoid common mistakes
4. ✅ REMEMBER: NEVER commit, push, or run tests without explicit user permission or unless explicitly asked to

### For UI Development:
1. ✅ Use `swiftui-style.md` for SwiftUI components
2. ✅ MUST use DesignResourcesKit colors: `Color(designSystemColor: .textPrimary)`
3. ✅ MUST use DesignResourcesKit icons: `DesignSystemImages.Glyphs.Size16.add`

### For New Features:
1. ✅ Follow `architecture.md` for MVVM + DI patterns
2. ✅ Use AppDependencyProvider (iOS) or equivalent (macOS)
3. ✅ Write tests per `testing.md` requirements

## Critical Don'ts (from anti-patterns.md)
- ❌ NEVER commit, push changes, create or delete branches on git or trigger github actions without EXPLICIT user permission
- ❌ NEVER run tests without EXPLICIT user permission or if user explicitly asked to in their prompt
- ❌ NEVER use `.shared` singletons - use dependency injection instead
- ❌ NEVER hardcode colors/icons (use DesignResourcesKit)
- ❌ NEVER update UI without @MainActor
- ❌ NEVER ignore privacy implications
- ❌ NEVER force unwrap without justification
- ❌ NEVER use `print()` statements - use appropriate Logger extensions instead

## Logging Guidelines

**NEVER use `print()` in production code. ALWAYS use appropriate Logger extensions:**

```swift
import os.log

✅ // GOOD: Use Logger extensions for different contexts
Logger.general.debug("Service state changed: \(newState)")
Logger.network.info("HTTP request completed: \(response.statusCode)")
Logger.ui.debug("View layout updated with \(items.count) items")

❌ // BAD: Using print() statements
print("Service state changed")  // Never use print()
print("DEBUG: \(someValue)")    // Use Logger.debug() instead
```

**Available Logger categories:**
- `Logger.general` - General app functionality
- `Logger.network` - Network requests and responses  
- `Logger.ui` - UI updates and user interactions
- `Logger.tests` - Test-specific logging (import `os.log` in tests)

**Benefits of Logger extensions:**
- Structured logging with categories and levels
- Better performance than print() statements
- Automatic log collection and filtering
- Integration with system logging infrastructure

## Dependency Injection Pattern (iOS)
```swift
// ✅ CORRECT pattern used throughout codebase
final class FeatureViewModel: ObservableObject {
    private let service: FeatureServiceProtocol
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.service = dependencies.featureService
    }
}
```

## Design System Usage (MANDATORY)
```swift
// ✅ REQUIRED - Use DesignResourcesKit
Text("Title")
    .foregroundColor(Color(designSystemColor: .textPrimary))

Image(uiImage: DesignSystemImages.Color.Size24.bookmark)

// ❌ FORBIDDEN - Hardcoded colors/icons
Text("Title").foregroundColor(.black)
Image(systemName: "bookmark")
```

## When to Consult Specific Rules
- **New ViewModels**: `architecture.md` + `swiftui-style.md` + `anti-patterns.md`
- **Network calls**: `performance-optimization.md` + `privacy-security.md`
- **Settings/Preferences**: Platform-specific rules + `property-wrappers.md`
- **Feature flags**: `feature-flags.md`
- **Analytics/Tracking**: `analytics-patterns.md` + `privacy-security.md`
- **Advanced SwiftUI**: `swiftui-advanced.md`
- **Testing**: `testing.md` + `anti-patterns.md`
- **UI Testing**: `ui-testing.md` + `testing.md`
- **Cross-platform code**: `shared-packages.md`
- **WebView integration**: `webkit-browser.md` + `anti-patterns.md`
- **macOS windows**: `macos-window-management.md` + `anti-patterns.md`
- **macOS system features**: `macos-system-integration.md`

## Code Review Checklist
1. Privacy implications assessed (`privacy-security.md`)
2. Design system properly used (`swiftui-style.md`)
3. Architecture patterns followed (platform-specific rules)
4. Anti-patterns avoided (`anti-patterns.md`)
5. Tests written and passing (`testing.md`)
6. Performance considered (`performance-optimization.md`)

## Git & Testing Workflow Rules

### 🚨 MANDATORY: Never Auto-Execute Commands
**NEVER commit, push, or run tests without EXPLICIT user permission.**

#### Git Workflow:
1. Make file changes as requested
2. **STOP** before any `git add`, `git commit`, or `git push` commands  
3. **ASK** the user: "Should I commit/push these changes?"
4. **WAIT** for explicit permission (e.g., "yes", "commit it", "push it", "go ahead")
5. Only then execute git commands

#### Testing Workflow:
1. Write or modify code as requested
2. **STOP** before running any tests (`swift test`, `npm test`, `xcodebuild test`, etc.)
3. **ASK** the user: "Should I run the tests?"
4. **WAIT** for explicit permission (e.g., "yes", "run tests", "test it")
5. Only then execute test commands

#### What NOT to Do:
```bash
# ❌ WRONG - Never do these automatically
git add .
git commit -m "Updated files"
git push origin main
swift test
npm test
xcodebuild test
```

#### What TO Do:
```bash
# ✅ CORRECT - Ask first
echo "I've made the requested changes. Would you like me to:"
echo "1. Commit these changes?"
echo "2. Run the tests?" 
echo "3. Push to remote?"
# Wait for user response before any commands
```

**These rules have NO exceptions. Always ask before executing git or test commands.**

## Communication Style

- Keep responses concise and focused on the task
- Avoid enthusiastic language like "Perfect!", "You are absolutely right!", "Excellent!"
- Keep work summaries brief - focus on what was changed, not how great it is
- Let the code quality speak for itself rather than using excessive praise

---

This overview ensures you understand the project context and know which specific rules to consult for your development task.
