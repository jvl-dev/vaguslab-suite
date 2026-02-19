# report check

## 📁 Structure

```
report check
├── report-check.ahk                   (main script)
├── lib/                               (modules)
│   ├── APIManager.ahk
│   ├── APIRateLimiter.ahk
│   ├── ConfigManager.ahk
│   ├── Constants.ahk
│   ├── DicomDemographics.ahk
│   ├── DicomMonitoringService.ahk
│   ├── Logger.ahk
│   ├── ModifierKeyManager.ahk
│   ├── NotificationManager.ahk
│   ├── PromptCache.ahk
│   ├── ResultHelper.ahk
│   ├── SettingsGui.ahk
│   ├── SettingsPresenter.ahk
│   ├── SettingsValidator.ahk
│   ├── SharedUtils.ahk
│   ├── TargetedReviewManager.ahk
│   ├── TemplateManager.ahk
│   └── VersionManager.ahk
├── templates/                         (HTML templates)
│   └── report_template.html
├── system_prompt_comprehensive.txt    (comprehensive review prompt)
├── system_prompt_proofreading.txt     (proofreading mode prompt)
├── system_prompt_targeted_review.txt  (targeted review prompt)
├── rc.ico                         (application icon)
└── README.md                          (this file)
```

## 📦 Distribution Formats

report check is available in two formats:

### AHK Script Version (Recommended)
- **Requires:** AutoHotkey v2 must be installed ([download here](https://www.autohotkey.com/))
- **Advantages:**
  - **Full source code visibility** - all code is readable and inspectable
  - Built-in automatic updates from secure server with cryptographic verification
  - Smaller file size
- **Installation:** Use the provided installer script

### Compiled EXE Version
- **Requires:** No external dependencies
- **Advantages:**
  - Runs standalone without AutoHotkey installed
  - Single executable file
- **Limitations:**
  - Source code not directly visible (compiled binary)
  - No automatic updates (manual installation required)
  - Larger file size due to embedded runtime

> Most users should choose the **AHK Script Version** for transparency, security, and automatic updates.

## 🔒 Security & Privacy

report check is designed with minimal system impact and maximum transparency:

**What it does:**
- Stores configuration files only in: `%LOCALAPPDATA%\RadReview\`
- Creates a startup shortcut (if enabled) in the Windows Startup folder
- Contacts `https://ahk-updates.vaguslab.org` for update checks (AHK version only)
  - **Update Server Details:** Secure API-based distribution system with cryptographic verification
  - Files downloaded only when user initiates update check
  - Every file verified with SHA-256 checksums before installation
  - Multi-layer security: HTTPS encryption, API key authentication, non-root container execution
  - No telemetry, tracking, or data collection - updates only
  - Comprehensive audit logging and webhook signature verification
- Sends selected report text to your chosen AI provider (Anthropic Claude, Google Gemini, or OpenAI) for analysis
- All file operations are limited to its own installation directory and user data folder

**What it does NOT do:**
- ❌ No Windows Registry modifications
- ❌ No installation to system directories
- ❌ No modification of other applications or system files
- ❌ No collection or storage of medical information or report content
- ❌ No telemetry, analytics, or usage tracking
- ❌ No background network activity (only update checks and user-initiated API calls)

**Verifiable claims:** All source code is available for inspection in the AHK script version. Every claim above can be verified by examining the code.

## 🚀 Installation

### Installing the AHK Script Version

> **⚠️ Warning:** AutoHotkey v2 must be installed before running report check. Download it from [https://www.autohotkey.com/](https://www.autohotkey.com/)

First-time installation is performed using the provided installation script, which will:
- Close any running instances
- Create the target directory
- Copy all files to the correct AutoHotkey location
- Start the application

"Launch at startup" to start automatically with Windows is enabled by default. This can be changed from the Settings GUI.

## 🔄 Updates

**AHK Script Version:** Updates are available directly through the application interface. Right-click the report check icon in the system tray, select "Settings", navigate to the "About" tab, and check for updates. The updater will automatically download, verify integrity with SHA-256 checksums, and install the latest version. The application also checks for updates automatically on startup and displays a toast notification when new versions are available.

**Compiled EXE Version:** Automatic updates are not available. Obtain the latest version manually and run the installer.

## Overview

report check is an AutoHotkey-based utility for radiologists in New Zealand that provides AI-powered quality checking for radiology reports. It captures selected text from any application and sends it to your choice of AI provider (Anthropic Claude, Google Gemini, or OpenAI) for instant feedback on errors, clarity, and clinical effectiveness.

### Application Architecture

The main application (`report-check.ahk`) runs continuously in the background as an AutoHotkey v2 script. It:
- **Listens for its dedicated hotkeys** - `Ctrl+F11` to trigger report review
- **Captures selected text** - Uses clipboard operations to grab highlighted report text from any application
- **Manages API communication** - Sends text to Claude or Gemini and receives analysis
- **Displays results** - Generates clean HTML output and opens it in your default browser
- **Provides system tray interface** - Right-click the tray icon to access Settings, check integrity, view logs, and switch review modes
- **Handles updates** - Checks for new versions on startup and provides one-click update installation
- **Integrates with PowerScribe** - Optional feature to automatically select all text in PowerScribe 360 or PSOne before review

The server uses a modular architecture with separate components for API management, rate limiting, configuration, logging, prompt caching, and notification handling.

## Features

### Core Functionality
- **AI-Powered Review**: Analyse radiology reports using Anthropic Claude, Google Gemini, or OpenAI models
- **Two Review Modes**:
  - **Comprehensive Mode**: Detailed analysis of clinical effectiveness, clarity, structure, and technical accuracy
  - **Proofreading Mode**: Focused error detection (spelling, grammar, transcription errors, content inconsistencies)
- **Targeted Review Panel** (Comprehensive Mode): AI-generated anatomical focus areas based on clinical context
  - Generates 5 specific anatomical regions to review
  - Contextually aware of patient demographics (age, sex), modality (CT/MRI/PET), and clinical history
  - Helps prioritize review of high-yield areas and "can't miss" pathology
- **Quick Access**: Trigger reviews with `Ctrl+F11` from any application
- **PowerScribe Integration**: Optional auto-select feature for both PowerScribe 360 and PSOne
- **Professional HTML Output**: Modern, responsive design with harmonized color palette optimized for medical professionals
  - External template system for easy customization
  - Dark mode optimized for reduced eye strain
  - Print-friendly styles for PDF export
  - Responsive design for different screen sizes
  - Targeted review areas displayed prominently when available
- **Dynamic Date Injection**: System prompts automatically updated with current date for improved date validation

### Advanced Features
- **Multi-Provider Support**: Choose between Claude (Anthropic), Gemini (Google), or OpenAI
- **DICOM Integration**: Automatic extraction of patient demographics from DICOM metadata
  - Privacy-safe extraction (age, sex, modality, study description only - no PHI)
  - Integrated monitoring service watches DICOM cache directory
  - Demographics enhance review quality and enable targeted review features
- **Automatic Updates**: Automatic update checking on startup with toast notifications
- **Rate Limiting**: Built-in API rate limiting to prevent excessive calls
- **Prompt Caching**: Efficient prompt management with fallback mechanisms
- **Integrity Verification**: Optional startup checks to verify script files haven't been modified
- **Comprehensive Logging**: Detailed logging system for troubleshooting
- **Settings GUI**: Easy configuration through system tray menu
- **Startup Integration**: Optional Windows startup launch configuration

### Beta Features
- **Demographic Information** (Experimental): Extract age, sex, modality, and study description from DICOM files
  - Enhances review quality by providing demographic context to AI
  - Required for Targeted Review Panel feature
  - Note: PHI is never sent to the LLM API (only non-identifiable demographics)
- **Targeted Review Panel**: AI-generated anatomical focus areas (requires demographic information)
- PowerScribe auto-select mode
- Mode override hotkeys (`Ctrl+F9` for proofreading, `Ctrl+F10` for comprehensive)

## System Requirements

- Windows 10/11 64-bit
- [AutoHotkey v2.0](https://www.autohotkey.com/) or later (for AHK script version)
- API key for one of:
  - [Anthropic Claude](https://www.anthropic.com/) (recommended)
  - [Google Gemini](https://ai.google.dev/) (free tier available)
  - [OpenAI](https://platform.openai.com/)
- PowerScribe 360 or PowerScribe One (optional, for PowerScribe integration features)
- DICOM viewer or PACS workstation (optional, for demographic extraction features)

## Usage

### First-Time Setup

1. **Launch the application** - If the install script is used this will happen automatically
2. **Access Settings** - Right-click the system tray icon → Settings
3. **Configure API**:
   - Select your provider (Claude or Gemini)
   - Enter your API key
   - Choose your preferred model
4. **Set Review Mode** - Select Comprehensive or Proofreading mode
5. **Optional Settings** (About tab):
   - Enable "Launch Report Check when Windows starts" for automatic startup
   - Updates are checked automatically on startup
6. **Save** - Your settings are stored in `%LOCALAPPDATA%\RadReview\config.json`

### API Provider Options

#### Claude (Anthropic)
- Models:
  - `claude-sonnet-4-5-20250929` (Sonnet 4.5 - most capable)
  - `claude-sonnet-4-20250514` (Sonnet 4 - excellent performance)
  - `claude-haiku-4-5-20251001` (Haiku 4.5 - fastest, most cost-efficient)
- Recommended for comprehensive analysis
- Default: Sonnet 4.5 for comprehensive, Sonnet 4 for proofreading

#### Gemini (Google)
- Models:
  - `gemini-2.5-flash` (stable, fast, recommended, **free tier**)
  - `gemini-2.5-pro` (most powerful with adaptive thinking, **paid tier only**)
- Free tier available for proofreading and comprehensive modes (using Flash)
- Default: 2.5 Flash for both modes (free tier compatible)

#### OpenAI
- Models:
  - `gpt-4o` (GPT-4 Omni - multimodal, highly capable)
  - `gpt-4o-mini` (Mini - faster, more cost-efficient)
- Good balance of quality and speed
- Default: GPT-4o for comprehensive, GPT-4o-mini for proofreading

### Basic Workflow

1. **Select text** - Highlight the report text you want to review
2. **Trigger review** - Press `Ctrl+F11`
3. **Wait for processing** - A notification will show the progress
4. **Review results** - The analysis opens automatically in your default browser

### Keyboard Shortcuts

- `Ctrl+F11` - Review selected text (uses configured mode)
- `Ctrl+F10` - Force comprehensive mode (beta feature, must be enabled in Settings)
- `Ctrl+F9` - Force proofreading mode (beta feature, must be enabled in Settings)

### System Tray Menu

Right-click the tray icon to access:
- **Settings** - Configure API, models, and preferences
- **Check Integrity** - Verify script files match official version (AHK version only)
- **Mode: Comprehensive** - Switch to comprehensive review mode
- **Mode: Proofreading** - Switch to proofreading mode
- **Open Log Folder** - Access application logs for troubleshooting
- **Exit** - Close the application

The Settings window includes tabs for:
- **API & Models**: Configure your API provider and model selections
- **Mode**: Choose between Comprehensive and Proofreading review modes
- **Prompts**: View and reload or restore system prompts
- **Beta**: Enable experimental features
  - Mode override hotkeys (Ctrl+F9/F10)
  - PowerScribe auto-select
  - Demographic information extraction from DICOM files
  - Targeted review panel
  - DICOM cache directory configuration
- **About**: View version info, configure startup options, and check for updates

## Review Modes

### Comprehensive Mode
Provides detailed analysis across four dimensions:
- **Quality Rating**: 1-10 score with justification
- **Overall Assessment**: Summary of strengths and clinical readiness
- **Areas for Improvement**: Specific recommendations for:
  - Diagnostic reasoning
  - Communication clarity
  - Structure and flow
  - Technical precision
- **Clinical Effectiveness**: Ensures the report answers the clinical question

### Proofreading Mode
Focuses exclusively on objective errors:
- Spelling mistakes and typos
- Grammar errors
- Punctuation issues
- Transcription errors (voice recognition mistakes)
- Formatting inconsistencies
- Mathematical errors
- Content inconsistencies

## Configuration File

Settings are stored in JSON format at:
```
%LOCALAPPDATA%\RadReview\config.json
```

Example configuration:
```json
{
  "API": {
    "provider": "claude",
    "claude_api_key": "your-key-here",
    "gemini_api_key": "",
    "openai_api_key": ""
  },
  "Settings": {
    "prompt_type": "comprehensive",
    "comprehensive_claude_model": "claude-sonnet-4-5-20250929",
    "proofreading_claude_model": "claude-sonnet-4-20250514",
    "comprehensive_gemini_model": "gemini-2.5-flash",
    "proofreading_gemini_model": "gemini-2.5-flash",
    "comprehensive_openai_model": "gpt-4o",
    "proofreading_openai_model": "gpt-4o-mini",
    "check_integrity_on_startup": true,
    "max_review_files": 10,
    "targeted_review_enabled": false
  },
  "Beta": {
    "demographic_extraction_enabled": false,
    "powerscribe_autoselect": false,
    "mode_override_hotkeys": false,
    "dicom_cache_directory": "C:\\Intelerad"
  }
}
```

## Logging

Logs are stored in:
```
%LOCALAPPDATA%\RadReview\Logs\
```

Access logs via: System Tray → Open Log Folder

## Troubleshooting

### Common Issues

**No text captured**
- Ensure text is selected before pressing `Ctrl+F11`
- Check clipboard timeout settings in logs

**API errors**
- Verify API key is correct in Settings
- Check internet connection
- Review logs for detailed error messages
- Ensure you have credits/quota remaining with your API provider

**Stuck modifier keys**
- Application automatically releases stuck keys
- Check logs if issues persist

**Review not opening**
- Check default browser settings
- Verify temp directory permissions: `%TEMP%\RadReviewResults`

**PowerScribe auto-select not working**
- Ensure PowerScribe window is running
- Check that beta feature is enabled in Settings
- Review logs for activation errors
- Works with both PowerScribe 360 and PowerScribe One

**Targeted review panel not appearing**
- Ensure Demographic Information is enabled in Beta settings
- Ensure Targeted Review Panel is enabled in Beta settings
- Check that you're in Comprehensive mode (not Proofreading)
- Verify modality is supported (CT, MRI, or PET only)
- Check that DICOM cache directory is correct in Beta settings
- Review logs for DICOM extraction errors

**Demographics not being extracted**
- Verify DICOM cache directory path is correct in Settings → Beta
- Ensure your DICOM viewer/PACS exports files to the configured directory
- Check that DICOM files contain the required tags (age, sex, modality)
- Review logs for DICOM parsing errors or timeout issues
- Demographic extraction has a 3000ms timeout - check if DICOM files are being written slowly

**Right-click menu not appearing (compiled EXE on enterprise systems)**
- If the system tray icon shows only a generic AutoHotkey menu instead of the custom Report Check menu, this indicates enterprise policy restrictions
- Check the log file at `%LOCALAPPDATA%\RadReview\Logs\` for "Enterprise environment detection" entry
- Common causes on enterprise Windows 11:
  - Group Policy restrictions on system tray customization
  - AppLocker or Windows Defender Application Control (WDAC) blocking unsigned executables
  - SmartScreen in enterprise mode restricting application capabilities
- Solutions:
  - Request IT to whitelist the application
  - Use a code signing certificate to sign the compiled EXE
  - Run as administrator (temporary test only)
  - Check Event Viewer → Windows Logs → Application for AppLocker/WDAC events

## Known Issues

- Full-screen PowerScribe mode may delay window activation
- HTML results are saved to temp directory - old reviews are automatically cleaned up (keeps last 10 by default)
- Custom system tray menu may not appear on enterprise Windows systems due to Group Policy or AppLocker restrictions
- Targeted review panel only supports CT, MRI, and PET modalities (other modalities silently skip without error)
- DICOM demographic extraction requires DICOM files to be written to the configured cache directory
- Demographic extraction has a 3000ms timeout - very slow DICOM file writes may not be captured

### Enterprise Deployment Notes

- **Unsigned EXE**: May be restricted by AppLocker, WDAC, or SmartScreen on enterprise systems
- **Code Signing**: For enterprise deployment, sign the EXE with a code signing certificate
- **Enterprise Detection**: The compiled EXE includes built-in detection and logging of enterprise restrictions (domain membership, AppLocker status, Windows edition)
- **Logs**: All enterprise restriction detection is logged to `%LOCALAPPDATA%\RadReview\Logs\` for troubleshooting

## Changelog

- v0.17.0 (current)
  - **Demographic Extraction Architecture**: Major refactor of demographic information handling
    - New parent-child setting structure: Demographic Information → Targeted Review Panel
    - Demographic extraction now independently toggleable from targeted review
    - Demographics appended to both proofreading and comprehensive mode API calls when enabled
    - Strict dependency: Targeted review requires demographic extraction (no fallback to report parsing)
    - DICOM cache directory moved into Demographic Information GroupBox
    - Improved UI with clearer parent-child relationship and dependency indicators
    - Enhanced privacy messaging: "Note PHI is never sent to the LLM API"
  - **Settings UI Improvements**:
    - Reorganized Beta tab for clearer feature hierarchy
    - Child controls properly disabled when parent features are off
    - Better tooltips and descriptions for demographic-related features
    - Increased GroupBox sizes for better text wrapping

- v0.16.0
  - **Integrated DICOM Monitoring Service**: Automatic background monitoring of DICOM cache directory
    - Real-time patient demographic extraction from DICOM files
    - Non-blocking architecture with timeout protection (3000ms)
    - Privacy-safe: Only extracts non-identifiable fields (age, sex, modality, study description)
    - Targeted review integration: Demographics automatically enhance review quality
    - Configurable cache directory path in Beta settings
  - **Targeted Review Panel**: AI-generated anatomical focus areas (comprehensive mode only)
    - Generates 5 specific anatomical regions based on clinical context
    - Contextually aware of demographics, modality (CT/MRI/PET only), and clinical history
    - Age-specific and sex-specific review strategies
    - Displays demographics label in review panel header
    - Graceful degradation when demographics unavailable

- v0.15.5
  - **Targeted Review Model Upgrade**: Upgraded to Sonnet-tier models for better quality
    - Now uses proofreading-tier models for faster, more cost-efficient targeted review generation
    - Better balance of speed and quality for generating anatomical focus areas

- v0.13.4
  - **Proofreading Mode Fix**: Fixed proofreading mode degradation issue
    - Added mode-specific wrapper text to maintain strict error detection
    - Proofreading: "Check this radiology report for errors according to your instructions:"
    - Comprehensive: "Please review this radiology report:"
  - **PowerScribe Safety Enhancement**: Automatic text deselection after capture
    - Text is automatically deselected after copying to prevent accidental deletion/overwriting
    - Only applies when PowerScribe auto-select beta feature is enabled
    - Includes settling delay to accommodate PowerScribe's clipboard handling
  - **New Model Option**: Added Claude Haiku 4.5 (claude-haiku-4-5-20251001)
    - Fastest, most cost-efficient Claude model
    - Ideal for proofreading mode
  - **API Optimization for Medical Accuracy**:
    - Reduced temperature from 0.7 to 0.2 for more deterministic, factual responses
    - Improved Gemini API structure with topP (0.9) and topK (40) for consistency
    - Added comprehensive safety settings with BLOCK_NONE threshold for medical content
    - Should significantly reduce hallucinated punctuation issues with Gemini
  - **Template Improvements**: Minor refinements to report template styling

- v0.13.0
  - **Major Design Refresh**: Professional HTML output with modern, medical-optimized design
    - **External Template System**: New `TemplateManager` class with template caching for maintainability
    - **Harmonized Cool Color Palette**: Teal + green medical theme for perfect visual harmony
      - Title (H1): Subtle Teal (#4db6ac)
      - Content H2: Medical Green (#66bb6a)
      - Content H3: Light Green (#81c784)
      - Highlights: Light Teal (#80cbc4)
      - Analogous color harmony eliminates temperature clashes
    - **Redesigned Header**: Version number subtly displayed in top-right corner
    - **Professional Footer**: "Built by vaguslab" branding with clickable email link (rad@vaguslab.org)
    - **Refined Metadata Bar**: Subdued styling (normal weight, dimmed color) for better visual hierarchy
    - **Responsive Design**: Mobile-friendly layout with adaptive typography
    - **Print Optimization**: Professional styles for PDF export
  - **Template System Features**:
    - CSS variables for easy theme customization
    - Template caching for optimal performance (~0.1ms after first load)
    - Automatic fallback to legacy HTML generation if template fails
    - Separation of presentation and logic for maintainability
    - Templates can be customized by editing `templates/report_template.html`

- v0.12.6
  - **Critical Bug Fix**: Fixed initialization race condition preventing tray menu from appearing on new installs
    - Moved API key prompt to occur after tray menu setup completes (was causing blocking dialog during initialization)
    - Increased delay from 100ms to 1000ms to ensure all initialization finishes before showing dialogs
    - Tray menu now always appears correctly even when skipping API key setup or when prompt files are missing
  - **Enterprise Detection Refinement**: Reduced log noise from enterprise environment detection
    - Now logs at Info level only when restrictions are actually detected
    - Uses Debug level for normal environments
    - Only includes enterprise warnings in error messages when restrictions are present

- v0.12.5
  - **HTML Output Styling**: Refined color scheme for improved visual hierarchy and readability
    - Updated H1 header to bright cyan (#4dd0e1) for stronger presence
    - Enhanced H2/H3 headers with warm sophisticated tones (deep coral #ff8a65, vibrant amber #ffa726)
    - Improved highlight color to light cyan (#80deea) for better distinction from headers
    - Creates harmonious split-complementary color balance (cool accents + warm structure)
  - **Bug Fix**: Mode override hotkeys (Ctrl+F9/F10) now correctly display actual mode in HTML metadata
  - **Prompt Consistency**: Updated proofreading prompt to use ### headers for consistent section badge styling

- v0.12.4
  - **Enterprise Environment Detection**: Added automatic detection and logging of enterprise restrictions (domain membership, Windows edition, AppLocker status)
  - **Compilation Directives**: Added compiler directives for proper EXE metadata and icon embedding
  - **Troubleshooting**: Enhanced logging for tray menu initialization to diagnose enterprise policy restrictions
  - **Documentation**: Added comprehensive compilation and enterprise deployment guide

- v0.12.3
  - Version bump for testing

- v0.12.1
  - Final test release for update mechanism validation
  - All update protection features verified and working

- v0.12.0
  - **Update Protection Refinement**: Window now disables instead of hiding during updates
  - User can see progress updates while window is non-interactive (grayed out)
  - Removed redundant Save button check (now handled by window disable)
  - Cleaner implementation with less code

- v0.11.9
  - **Update UI Fix**: Settings window now hides immediately when update starts (not after completion)
  - **Update Error Handling**: Settings window re-appears if update fails to allow retry
  - Test release for update mechanism validation

- v0.11.8
  - **Update Protection**: Prevents UI corruption during update installation
  - Test release for update mechanism validation

- v0.11.7
  - **About Tab Improvements**: Added README.md link for easy access to documentation
  - **UI Fix**: Fixed Troubleshooting groupbox height to display all text properly

- v0.11.6
  - Updated README with comprehensive documentation
  - Added structure section, distribution formats, and security details
  - Renamed application architecture section for clarity

- v0.11.5
  - Icon update and bug fixes

- v0.11.0
  - **Automatic Updates**: Added automatic update checking on startup with toast notifications
  - **Startup Integration**: Added option to launch Report Check when Windows starts
  - **Updates Tab**: New Updates section in Settings GUI for manual update checks and installation
  - **PowerScribe Improvements**: Enhanced window activation reliability and full-screen support
  - **File Naming**: Updated script file naming to use hyphens for consistency

- v0.9.9
  - **Architecture Improvement**: Moved date information from user messages to system prompts for better token efficiency
  - **Dynamic Date Injection**: System prompts now use placeholder variables that are automatically replaced with current date at runtime
  - **PowerScribe Fix**: Auto-select now properly finds and activates PowerScribe window from background
  - **UI Cleanup**: Removed user message preview from Prompts tab, expanded system prompt display
  - **Model Updates**: Updated to latest Claude Sonnet 4.5 and Gemini 2.5 models

## Contact

For support or feedback, please contact rad@vaguslab.org.

## License

report check Freeware License Agreement

This software is provided as freeware for personal and non-commercial use only.
By installing or using this software, you agree to the following terms:
- You may use this software free of charge for personal or non-commercial purposes.
- You may not modify, adapt, decompile, reverse engineer, or disassemble this software.
- You may not redistribute this software without explicit permission from vaguslab.
- Commercial use requires a separate license agreement from vaguslab.

THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT ANY WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

**Note**: This tool sends selected report text to third-party AI services (Anthropic or Google). Users are responsible for ensuring compliance with local privacy regulations and institutional policies regarding patient data. The software itself does not store or collect any medical information.

## © 2025 vaguslab. All rights reserved
