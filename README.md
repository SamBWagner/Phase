# Phase

A macOS application for monitoring .NET installation health and version status.

## Overview

Phase scans your system for installed .NET SDKs, runtimes, and hosts, then analyzes their health status by comparing against the latest official releases from Microsoft. It helps you quickly identify outdated installations and maintain a healthy .NET development environment.

## Features

- **Automatic .NET Discovery**: Scans common installation paths and uses the `dotnet` CLI to find all installed versions
- **Health Analysis**: Compares installed versions against the latest releases to identify:
  - Up-to-date installations
  - Out-of-date versions
  - Unsupported versions
  - Missing versions
- **Version Tracking**: Monitors Current, Previous, and LTS (Long Term Support) .NET releases
- **Offline Support**: Falls back to cached version data when network is unavailable
- **Clean UI**: Simple, intuitive interface with color-coded health status indicators

## How It Works

1. **Scanning**: Phase attempts to locate .NET installations using:
   - The `dotnet` CLI (`--list-sdks`, `--list-runtimes`, `--info`)
   - Direct directory scanning at `/usr/local/share/dotnet`
   - Optional manual folder selection (macOS security authorization)

2. **Version Fetching**: Retrieves the latest .NET release information from Microsoft's official releases-index

3. **Health Analysis**: Compares installed SDK versions against expected versions for:
   - Current release
   - Previous release
   - LTS release

