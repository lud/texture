# Changelog

All notable changes to this project will be documented in this file.

## [1.2.1] - 2026-08-07

### 🐛 Bug Fixes

- Fixed URI template parsing of apostrophes in literals and percent-encoded variable names (_lud_)

## [1.2.0] - 2026-07-03

### 🚀 Features

- Implement HTTP Structured Fields RFC 9651 (backwards compatible) (_lud_)

## [1.1.1] - 2026-07-03

### ⚡ Performance

- URI templates parser now adds 'end of string' marker at parse-time (_lud_)

## [1.1.0] - 2026-07-03

### 🚀 Features

- Added support for lists of tuples as ordered key/value pairs in URI template rendering (_lud_)

### 🐛 Bug Fixes

- Fixed subtle bugs in URI template matching algorithms (_lud_)

### 📚 Documentation

- Added docs for public API (_lud_)

## [1.0.1] - 2026-05-29

### ⚙️ Miscellaneous Tasks

- Fixed Compilation warnings for Elixir 1.20 (_lud_)

## [1.0.0] - 2026-04-22

### ⚙️ Miscellaneous Tasks

- Releasing under the Apache license version 2.0 (_lud_)

## [0.3.2] - 2025-11-15

### 🐛 Bug Fixes

- Correctly handle unmatched literals in URI templates (_lud_)

## [0.3.1] - 2025-11-10

### 🚀 Features

- Implement Inspect for UriTemplate (_lud_)

## [0.3.0] - 2025-11-09

### 🚀 Features

- Added limited URI template matching capability (_lud_)

### 📚 Documentation

- URI matching does not support prefix truncation (_lud_)

## [0.2.1] - 2025-11-04

### 🚀 Features

- Support exploding scalar values (_lud_)

## [0.2.0] - 2025-11-04

### 🚜 Refactor

- Rewrote the UriTemplate rendered (_lud_)

### 📚 Documentation

- Fix doc examples (_lud_)

## [0.1.0] - 2025-09-15

### 🚀 Features

- Added the uri-template parser (_lud_)
- Added Http Structured Fields parser (_lud_)

### 📚 Documentation

- Added documentation for HTTP Structured Fields (_lud_)
- Documentation for URI Templates (_lud_)

### ⚙️ Miscellaneous Tasks

- Configure dialyzer (_lud_)

