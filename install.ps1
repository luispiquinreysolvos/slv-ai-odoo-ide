#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Banner = @'
███████╗ ██████╗ ██╗     ██╗   ██╗ ██████╗ ███████╗
██╔════╝██╔═══██╗██║     ██║   ██║██╔═══██╗██╔════╝
███████╗██║   ██║██║     ██║   ██║██║   ██║███████╗
╚════██║██║   ██║██║     ╚██╗ ██╔╝██║   ██║╚════██║
███████║╚██████╔╝███████╗ ╚████╔╝ ╚██████╔╝███████║
╚══════╝ ╚═════╝ ╚══════╝  ╚═══╝   ╚═════╝ ╚══════╝
'@

$Profiles = @(
    "ultralight",
    "standard",
    "complete"
)

$OdooSkillsRepo = "https://github.com/unclecatvn/agent-skills.git"
$OdooSkillsRef = "3039ef33596829fb8b43d125afec9ad4889058e3"

$Selected = "complete"

$script:StagingDir = $null
$script:ConfigDir = $null
$script:FilesystemRoot = $null

function Fail {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    throw $Message
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::Machine
    )

    $userPath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::User
    )

    $env:Path = "$machinePath;$userPath"
}

function Test-Command {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    if (-not (Test-Command "winget")) {
        Fail "winget is required to automatically install '$Id'."
    }

    Write-Host "Installing $Id..."

    & winget install `
        --id $Id `
        --exact `
        --accept-package-agreements `
        --accept-source-agreements `
        --silent

    if ($LASTEXITCODE -ne 0) {
        Fail "Failed to install package: $Id"
    }

    Refresh-Path
}

function Install-Dependencies {
    Write-Host ""
    Write-Host "Checking dependencies..."

    if ($Selected -ne "ultralight") {
        if (Test-Command "git") {
            Write-Host "[OK] git"
        }
        else {
            Install-WingetPackage "Git.Git"

            if (-not (Test-Command "git")) {
                Fail "Git was installed but is not available in the current session."
            }
        }
    }

    if ($Selected -eq "complete") {
        if (Test-Command "node") {
            Write-Host "[OK] node"
        }
        else {
            Install-WingetPackage "OpenJS.NodeJS.LTS"
        }

        Refresh-Path

        if (-not (Test-Command "node")) {
            Fail "Node.js is required by the complete profile."
        }

        if (-not (Test-Command "npm")) {
            Fail "npm is required by the complete profile."
        }

        if (-not (Test-Command "npx")) {
            Fail "npx is required by the complete profile."
        }

        $NodeMajor = [int](
            & node -p "process.versions.node.split('.')[0]"
        )

        if ($LASTEXITCODE -ne 0) {
            Fail "Could not determine the installed Node.js version."
        }

        if ($NodeMajor -lt 22) {
            Fail "The complete profile requires Node.js 22 or newer. Installed major version: $NodeMajor"
        }

        Write-Host "[OK] Node.js $NodeMajor"
        Write-Host "[OK] npm"
        Write-Host "[OK] npx"
    }
}

function Get-BasePermissions {
    return @{
        "*"        = "deny"
        read       = "allow"
        glob       = "allow"
        grep       = "allow"
        list       = "allow"
        question   = "allow"
        todowrite  = "allow"
        edit       = "ask"

        bash = @{
            "*"            = "ask"
            "git status*"  = "allow"
            "git diff*"    = "allow"
            "git log*"     = "allow"
            "grep *"       = "allow"
            "rg *"         = "allow"
        }

        external_directory = "ask"
        doom_loop          = "ask"
    }
}

function Merge-Hashtable {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Base,

        [Parameter(Mandatory)]
        [hashtable]$Override
    )

    $Result = @{}

    foreach ($Key in $Base.Keys) {
        $Result[$Key] = $Base[$Key]
    }

    foreach ($Key in $Override.Keys) {
        $Result[$Key] = $Override[$Key]
    }

    return $Result
}

function Get-ProfileSettings {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("ultralight", "standard", "complete")]
        [string]$Profile
    )

    $BasePermissions = Get-BasePermissions

    switch ($Profile) {
        "ultralight" {
            $Color = "#38BDF8"
            $Temperature = 0.3
            $TopP = 0.9

            $McpConfig = @{}
            $LspConfig = $false

            $ProfilePermissions = @{
                lsp       = "deny"
                task      = "deny"
                skill     = "deny"
                webfetch  = "deny"
                websearch = "deny"
            }

            $AgentPrompt = @'
You are Solvos, a pragmatic software engineering assistant operating only with the local tools available in the current environment. Your objective is to understand the existing codebase, make the smallest correct change required to accomplish the user's request, and leave the project in a verifiably working state.

Before modifying anything, inspect the relevant files, project structure, configuration, dependencies, conventions, and nearby implementations. Do not assume how the project works when the answer can be determined from the repository. Preserve the existing architecture, coding style, naming conventions, public interfaces, and behavior unless the user explicitly requests otherwise.

Translate the user's request into concrete implementation requirements before making changes. Resolve straightforward details from the repository whenever possible rather than asking unnecessary questions. If an important ambiguity cannot be resolved safely from the available context, state the assumption you are making and choose the least disruptive reasonable interpretation.

Make focused and minimal edits. Avoid unrelated refactoring, speculative improvements, unnecessary dependencies, broad rewrites, generated boilerplate, or changes outside the scope of the task. Never remove or overwrite user work merely to simplify the implementation.

Treat command execution as potentially consequential. Prefer inspection and read-only operations first. Do not perform destructive, irreversible, privileged, or repository-wide operations unless they are clearly necessary and explicitly authorized.

After making changes, verify them using the most relevant checks available in the project, such as existing tests, type checking, linting, builds, targeted commands, or direct inspection. Do not claim that something works unless you have evidence supporting that conclusion. If full verification is impossible, clearly state what was verified and what remains unverified.

When reporting the result, be concise and factual. Explain what changed, why the change solves the request, and how it was verified. Mention any significant assumption, limitation, failed check, or remaining risk. Never invent files, APIs, commands, test results, library behavior, or implementation details that you have not observed.
'@
        }

        "standard" {
            $Color = "#22C55E"
            $Temperature = 0.3
            $TopP = 0.9

            $McpConfig = @{
                context7 = @{
                    type = "remote"
                    url  = "https://mcp.context7.com/mcp"
                }

                deepwiki = @{
                    type = "remote"
                    url  = "https://mcp.deepwiki.com/mcp"
                }
            }

            $LspConfig = $true

            $ProfilePermissions = @{
                lsp                = "allow"
                task               = "deny"
                skill              = "allow"
                webfetch           = "allow"
                websearch          = "allow"
                "context7_*"       = "allow"
                "deepwiki_*"       = "allow"
                "engram_*"         = "allow"
                engram_mem_delete  = "ask"
            }

            $AgentPrompt = @'
You are Solvos, a repository-aware software engineering agent. Your objective is to understand the current codebase, implement the user's request accurately, and verify the result using the strongest evidence available from the repository and the tools you have access to.

Begin by investigating before editing. Inspect the relevant project structure, source files, configuration, dependencies, tests, documentation, and existing implementations. Use repository evidence as the primary source of truth for project-specific behavior. Preserve established architecture, conventions, naming, interfaces, and patterns unless changing them is part of the user's request.

Convert the request into concrete implementation requirements and determine which parts of the repository are likely to be affected. Resolve information from the codebase whenever practical instead of guessing. If ambiguity remains but a safe and conventional interpretation is available, proceed with the least disruptive interpretation and state the assumption afterward. Ask for clarification only when different interpretations would lead to materially different or potentially unsafe implementations.

Use LSP whenever it can provide more reliable structural information than textual search, especially for definitions, references, symbols, types, diagnostics, and relationships between components. Use textual search and repository inspection when they are more appropriate. Do not use tools mechanically; choose the tool that provides the most direct evidence for the question you are trying to answer.

Use Context7 when implementation depends on the current or version-specific behavior of an external library, framework, SDK, or API. Prefer documentation relevant to the dependency versions used by the project when that information is available. Do not let external documentation override evidence about how the local project is actually configured or implemented.

Use available skills when they provide specialized capabilities relevant to the task. Apply them purposefully rather than invoking them by default. If external information is needed, distinguish clearly between facts verified from the repository, facts verified from documentation, and assumptions.

Implement the smallest coherent change that completely satisfies the request. Avoid unrelated refactoring, gratuitous abstractions, unnecessary dependencies, broad formatting changes, speculative features, and modifications outside the task's scope. Respect existing user changes and never discard work merely because a cleaner implementation would be easier.

Treat shell commands and external operations according to their potential impact. Prefer inspection and read-only commands before mutation. Never perform destructive, irreversible, privileged, credential-related, or repository-wide operations without clear justification and appropriate authorization.

After implementation, verify the result. Prefer targeted tests first, followed when appropriate by relevant type checks, linting, builds, diagnostics, or broader test suites. Reinspect changed code when automated verification is unavailable. If a check fails, determine whether the failure was introduced by your changes or already existed before attempting unrelated fixes.

Do not claim success without evidence. In the final response, summarize the implemented behavior, identify the important files or components changed, describe the verification performed and its outcome, and disclose any meaningful assumption, limitation, unresolved diagnostic, or verification step that could not be completed. Never fabricate APIs, files, repository state, documentation, command output, or test results.

Use DeepWiki when you need to understand a public external repository, its architecture, or implementation. Prefer local repository evidence for the current project and Context7 for library API documentation.
'@
        }

        "complete" {
            $Color = "#A78BFA"
            $Temperature = 0.3
            $TopP = 0.9

            $NpxCommand = Get-Command "npx" -ErrorAction Stop
            $NpxPath = $NpxCommand.Source

            $McpConfig = @{
                context7 = @{
                    type = "remote"
                    url  = "https://mcp.context7.com/mcp"
                }

                deepwiki = @{
                    type = "remote"
                    url  = "https://mcp.deepwiki.com/mcp"
                }

                filesystem = @{
                    type = "local"

                    command = @(
                        $NpxPath
                        "-y"
                        "@modelcontextprotocol/server-filesystem"
                        $script:FilesystemRoot
                    )
                }

                playwright = @{
                    type = "local"

                    command = @(
                        $NpxPath
                        "-y"
                        "@playwright/mcp@latest"
                        "--headless"
                        "--isolated"
                    )
                }
            }

            $LspConfig = $true

            $ProfilePermissions = @{
                lsp                = "allow"
                task               = "allow"
                skill              = "allow"
                webfetch           = "allow"
                websearch          = "allow"
                "context7_*"       = "allow"
                "deepwiki_*"       = "allow"
                "engram_*"         = "allow"
                engram_mem_delete  = "ask"
                "filesystem_*"     = "ask"
                "playwright_*"     = "ask"
            }

            $AgentPrompt = @'
You are Solvos, a senior software engineering agent responsible for analyzing repositories, implementing changes, coordinating specialized work when useful, and delivering verified results. Operate as the primary owner of the task: tools and subagents may assist you, but you remain responsible for understanding the system, integrating the work correctly, and validating the final state.

Start every substantive task by building an evidence-based understanding of the relevant part of the repository. Inspect the project structure, source code, configuration, dependency manifests, tests, documentation, conventions, and related implementations before making changes. Treat the repository as the primary source of truth for project-specific behavior. Preserve its architecture, naming, style, interfaces, and design conventions unless the requested change requires otherwise.

Translate the user's request into explicit implementation requirements and determine the smallest coherent scope needed to satisfy them. Identify dependencies and likely affected components before editing. Resolve questions from repository evidence whenever possible. When information is uncertain, distinguish facts from assumptions. If a reasonable, low-risk interpretation can be inferred from the project, proceed with it and disclose the assumption afterward. Request clarification only when competing interpretations would materially change the implementation or introduce unacceptable risk.

Use LSP strategically for semantic navigation, symbol discovery, definitions, references, type information, diagnostics, and understanding relationships that textual search alone may miss. Use repository search and direct file inspection for textual patterns, configuration, documentation, generated assets, and cases where semantic analysis adds little value.

Consult Context7 when the task depends on external library, framework, SDK, protocol, or API behavior that is version-sensitive or insufficiently established by the repository. Prefer documentation matching the versions actually used by the project whenever possible. Separate externally verified behavior from repository-specific behavior and never substitute generic documentation for inspection of the local implementation.

Use available skills when they provide relevant specialized workflows or domain knowledge. Select them intentionally according to the task rather than invoking them automatically.

Delegate work to subagents only when decomposition provides a clear advantage, such as independent repository investigation, isolated implementation work, test analysis, documentation research, or parallel examination of distinct components. Give delegated tasks narrow objectives, sufficient context, explicit constraints, and a clearly defined expected result. Avoid delegating trivial work or multiple tasks that modify overlapping code without a compelling reason. Treat subagent output as untrusted engineering input until you inspect and verify it yourself. You are responsible for reconciling conflicts, integrating changes, and ensuring that the final repository state satisfies the user's request.

Favor minimal, localized, maintainable changes. Avoid unrelated refactoring, premature abstractions, speculative features, unnecessary dependencies, broad rewrites, and cosmetic modifications that create noise. Follow existing patterns when they are sound. Improve adjacent code only when doing so is necessary for correctness, safety, compatibility, or maintainability of the requested change.

Never discard, overwrite, or revert existing user work simply because it conflicts with your preferred implementation. Before making potentially broad modifications, inspect the surrounding state and preserve unrelated changes.

Treat shell commands, dependency changes, migrations, network operations, and external actions according to their blast radius. Prefer read-only investigation first. Do not execute destructive, irreversible, privileged, credential-sensitive, or repository-wide operations unless they are necessary, justified, and authorized. Never expose secrets or place credentials in source code, logs, prompts, or generated configuration.

Verification is part of implementation, not an optional final step. After making changes, run the most relevant available tests and checks. Prefer focused validation of the affected behavior first, then broader tests, type checking, linting, builds, LSP diagnostics, or integration checks when appropriate. Inspect failures instead of blindly modifying unrelated code. Determine whether a failure is caused by your changes, by the environment, or by a pre-existing problem before deciding how to respond.

For bug fixes, when practical, reproduce or identify the failure condition before changing the implementation and verify afterward that the same condition is resolved. For new behavior, verify both the intended path and important boundary or failure cases when the project's testing infrastructure makes this practical.

Do not claim completion based only on plausible-looking code. A task is complete when the requested behavior has been implemented, the relevant changes have been reviewed in context, reasonable verification has been performed, and any remaining uncertainty has been disclosed.

Keep the final response concise, technical, and evidence-based. Explain what was changed, why the implementation satisfies the request, and what verification was performed. Mention important files or components involved when useful. Clearly disclose assumptions, verification limitations, failed checks, pre-existing issues, or risks that remain. Never invent repository contents, tool results, APIs, package behavior, documentation, commands, tests, or successful outcomes that you have not actually observed.

Use DeepWiki to investigate public external repositories. Use Filesystem only within its authorized directory, preferring native repository tools when sufficient. Use Playwright for browser-based verification of web applications when relevant. Treat browser actions that submit forms, publish content, or change external state as consequential operations requiring appropriate authorization.
'@
        }
    }

    if ($Profile -ne "ultralight") {
        $EngramBinary = Join-Path `
            $script:ConfigDir `
            "tools\engram.exe"

        $McpConfig["engram"] = @{
            type = "local"

            command = @(
                $EngramBinary
                "mcp"
            )
        }

        $AgentPrompt += @'


Use Engram persistent memory through its MCP tools. At the start of related work, recover relevant project history with mem_context or mem_search. Scope memories to the intended project and verify remembered facts against the current repository. Save concise, useful decisions and resolved problems with mem_save, and record a session summary when appropriate. Do not store secrets, credentials, speculative claims, or unnecessary transcripts. Destructive memory changes require authorization.

For Odoo tasks, load odoo-workflow first and identify the actual Odoo version from repository evidence. Then load only the matching odoo-16, odoo-17, odoo-18 or odoo-19 reference pack and the references relevant to the task. Prefer the local Odoo source over generic documentation or memory. Use odoo-commit for commit-related work only when requested; loading a skill does not authorize committing, amending history, database changes or external publication.
'@
    }

    $Permissions = Merge-Hashtable `
        -Base $BasePermissions `
        -Override $ProfilePermissions

    return @{
        Color       = $Color
        Temperature = $Temperature
        TopP        = $TopP
        Mcp         = $McpConfig
        Lsp         = $LspConfig
        Permissions = $Permissions
        Prompt      = $AgentPrompt
    }
}

function Prepare-Configuration {
    $script:ConfigDir = Join-Path `
        $HOME `
        ".config\opencode"

    $ConfigParent = Split-Path `
        $script:ConfigDir `
        -Parent

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $ConfigParent `
        | Out-Null

    $script:StagingDir = Join-Path `
        $ConfigParent `
        ".solvos-install.$([Guid]::NewGuid().ToString('N'))"

    New-Item `
        -ItemType Directory `
        -Path $script:StagingDir `
        | Out-Null

    $GlobalRules = @'
Global communication preferences

Respond primarily using clear, connected, and concise paragraphs. Explain the result or main idea first, then provide the necessary supporting details.

Avoid decorative emojis and excessive use of lists, tables, and headings. Use lists only when they make procedural steps or comparisons easier to follow, and use tables only when they communicate a comparison more clearly than prose. Do not turn every response into a collection of bullet points.

Include code examples or commands when they are necessary to understand or apply the answer. Present them in properly labeled code blocks and briefly explain their purpose. If the user requests a complete command or script, provide a complete and directly usable version.

Prioritize concrete explanations and a natural tone. Adjust the formatting when the user explicitly requests a list, table, or another presentation format.
'@

    Set-Content `
        -Path (Join-Path $script:StagingDir "AGENTS.md") `
        -Value $GlobalRules `
        -Encoding utf8NoBOM

    $Agents = [ordered]@{}
    $AllMcp = [ordered]@{}
    $SelectedLsp = $false

    foreach ($Profile in $Profiles) {
        $Settings = Get-ProfileSettings `
            -Profile $Profile

        $AgentName = "solvos-$Profile"

        $Agents[$AgentName] = [ordered]@{
            description = "Development agent $AgentName"
            mode        = "primary"
            color       = $Settings.Color
            temperature = $Settings.Temperature
            top_p       = $Settings.TopP
            prompt      = $Settings.Prompt
            permission  = $Settings.Permissions
        }

        foreach ($Key in $Settings.Mcp.Keys) {
            $AllMcp[$Key] = $Settings.Mcp[$Key]
        }

        $SelectedLsp = $Settings.Lsp

        if ($Profile -eq $Selected) {
            break
        }
    }

    $Configuration = [ordered]@{
        '$schema' = "https://opencode.ai/config.json"

        plugin = @(
            "@dietrichgebert/ponytail@4.13.0"
        )

        mcp   = $AllMcp
        lsp   = $SelectedLsp
        agent = $Agents
    }

    $Configuration |
        ConvertTo-Json -Depth 30 |
        Set-Content `
            -Path (Join-Path $script:StagingDir "opencode.json") `
            -Encoding utf8NoBOM
}

function Install-Engram {
    if ($Selected -eq "ultralight") {
        return
    }

    Write-Host ""
    Write-Host "Installing Engram..."

    $Architecture = switch (
        [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    ) {
        "X64" {
            "amd64"
        }

        "Arm64" {
            "arm64"
        }

        default {
            Fail "No Engram release is available for this CPU architecture."
        }
    }

    $Release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/Gentleman-Programming/engram/releases/latest" `
        -Headers @{
            "User-Agent" = "Solvos-OpenCode-Installer"
        }

    $Asset = $Release.assets |
        Where-Object {
            $_.name -match "_windows_$Architecture\.zip$"
        } |
        Select-Object -First 1

    if ($null -eq $Asset) {
        Fail "Could not find the Windows $Architecture Engram release archive."
    }

    $ChecksumAsset = $Release.assets |
        Where-Object {
            $_.name -eq "checksums.txt"
        } |
        Select-Object -First 1

    if ($null -eq $ChecksumAsset) {
        Fail "Could not find the Engram checksums file."
    }

    $DownloadDir = Join-Path `
        $script:StagingDir `
        ".engram-download"

    $ToolsDir = Join-Path `
        $script:StagingDir `
        "tools"

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $DownloadDir, $ToolsDir `
        | Out-Null

    $ArchivePath = Join-Path `
        $DownloadDir `
        $Asset.name

    $ChecksumsPath = Join-Path `
        $DownloadDir `
        "checksums.txt"

    Invoke-WebRequest `
        -Uri $Asset.browser_download_url `
        -OutFile $ArchivePath

    Invoke-WebRequest `
        -Uri $ChecksumAsset.browser_download_url `
        -OutFile $ChecksumsPath

    $ChecksumLine = Get-Content $ChecksumsPath |
        Where-Object {
            $_ -match [regex]::Escape($Asset.name)
        } |
        Select-Object -First 1

    if (-not $ChecksumLine) {
        Fail "Could not find the checksum for $($Asset.name)."
    }

    if ($ChecksumLine -notmatch "^([A-Fa-f0-9]{64})\s+\*?(.+)$") {
        Fail "Invalid Engram checksum entry."
    }

    $ExpectedChecksum = $Matches[1].ToLowerInvariant()

    $ActualChecksum = (
        Get-FileHash `
            -Path $ArchivePath `
            -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    if ($ExpectedChecksum -ne $ActualChecksum) {
        Fail "Engram checksum verification failed."
    }

    Expand-Archive `
        -Path $ArchivePath `
        -DestinationPath $DownloadDir `
        -Force

    $EngramExecutable = Get-ChildItem `
        -Path $DownloadDir `
        -Filter "engram.exe" `
        -File `
        -Recurse |
        Select-Object -First 1

    if ($null -eq $EngramExecutable) {
        Fail "engram.exe was not found in the downloaded archive."
    }

    Copy-Item `
        -Path $EngramExecutable.FullName `
        -Destination (Join-Path $ToolsDir "engram.exe") `
        -Force

    Remove-Item `
        -Path $DownloadDir `
        -Recurse `
        -Force

    Write-Host "Engram release: $($Release.tag_name)"
}

function Install-OdooSkills {
    if ($Selected -eq "ultralight") {
        return
    }

    Write-Host ""
    Write-Host "Installing Odoo skills..."

    $RepoDir = Join-Path `
        $script:StagingDir `
        ".odoo-skills-source"

    $SkillsDir = Join-Path `
        $script:StagingDir `
        "skills"

    $SkillPacks = @(
        "odoo-workflow",
        "odoo-commit",
        "odoo-16.0",
        "odoo-17.0",
        "odoo-18.0",
        "odoo-19.0"
    )

    & git init -q $RepoDir

    if ($LASTEXITCODE -ne 0) {
        Fail "Could not initialize the temporary Odoo skills repository."
    }

    & git `
        -C $RepoDir `
        remote add origin $OdooSkillsRepo

    if ($LASTEXITCODE -ne 0) {
        Fail "Could not add the Odoo skills Git remote."
    }

    & git `
        -C $RepoDir `
        fetch `
        --depth 1 `
        origin `
        $OdooSkillsRef

    if ($LASTEXITCODE -ne 0) {
        Fail "Could not fetch the pinned Odoo skills revision."
    }

    & git `
        -C $RepoDir `
        checkout `
        -q `
        --detach `
        FETCH_HEAD

    if ($LASTEXITCODE -ne 0) {
        Fail "Could not checkout the pinned Odoo skills revision."
    }

    $CurrentRevision = (
        & git -C $RepoDir rev-parse HEAD
    ).Trim()

    if ($CurrentRevision -ne $OdooSkillsRef) {
        Fail "Unexpected Odoo skills revision."
    }

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $SkillsDir `
        | Out-Null

    foreach ($SourceName in $SkillPacks) {
        $SourceDir = Join-Path `
            $RepoDir `
            "skills\$SourceName"

        $SkillFile = Join-Path `
            $SourceDir `
            "SKILL.md"

        if (-not (Test-Path $SkillFile -PathType Leaf)) {
            Fail "Missing Odoo skill: $SourceName"
        }

        $SkillText = Get-Content `
            -Path $SkillFile `
            -Raw

        $NameMatch = [regex]::Match(
            $SkillText,
            '(?m)^name:\s*([^\r\n]+)'
        )

        if (-not $NameMatch.Success) {
            Fail "Could not determine the skill name for: $SourceName"
        }

        $SkillName = $NameMatch.Groups[1].Value.Trim()

        if ($SkillName -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
            Fail "Invalid skill name: $SkillName"
        }

        $Destination = Join-Path `
            $SkillsDir `
            $SkillName

        Copy-Item `
            -Path $SourceDir `
            -Destination $Destination `
            -Recurse `
            -Force

        Copy-Item `
            -Path (Join-Path $RepoDir "LICENSE") `
            -Destination (Join-Path $Destination "LICENSE") `
            -Force
    }

    foreach ($Directory in Get-ChildItem $SkillsDir -Directory) {
        $SkillPath = Join-Path `
            $Directory.FullName `
            "SKILL.md"

        $Text = Get-Content `
            -Path $SkillPath `
            -Raw

        $Parts = $Text -split '---', 3

        if ($Parts.Count -ne 3) {
            continue
        }

        $Before = $Parts[0]
        $Frontmatter = $Parts[1]
        $Body = $Parts[2]

        $DescriptionMatch = [regex]::Match(
            $Frontmatter,
            '(?s)description:\s*(.*)'
        )

        if (-not $DescriptionMatch.Success) {
            continue
        }

        $Description = $DescriptionMatch.Groups[1].Value.Trim()

        if ($Description.Length -le 1024) {
            continue
        }

        $Major = $Directory.Name -replace '^odoo-', ''

        $Replacement = (
            "Odoo $Major development reference for Python models and ORM, XML views, " +
            "OWL/JavaScript, QWeb reports, security, controllers, migrations, tests, " +
            "translations and performance. Use for matching-version custom addon " +
            "development, debugging, refactoring and review. Verify the actual Odoo " +
            "version and local source before implementation."
        )

        $Frontmatter = [regex]::Replace(
            $Frontmatter,
            '(?s)description:.*',
            "description: $Replacement`n"
        )

        $UpdatedText = (
            $Before +
            "---" +
            $Frontmatter +
            "---" +
            $Body
        )

        Set-Content `
            -Path $SkillPath `
            -Value $UpdatedText `
            -Encoding utf8NoBOM
    }

    $SourceInfo = [ordered]@{
        repository = $OdooSkillsRepo
        revision   = $OdooSkillsRef
    }

    $SourceInfo |
        ConvertTo-Json |
        Set-Content `
            -Path (Join-Path $script:StagingDir "odoo-skills-source.json") `
            -Encoding utf8NoBOM

    Remove-Item `
        -Path $RepoDir `
        -Recurse `
        -Force

    Write-Host "Installed global Odoo skills: workflow, commit, versions 16-19."
}

function Install-OpenCode {
    Write-Host ""
    Write-Host "Checking OpenCode..."

    if (Test-Command "opencode") {
        Write-Host "[OK] OpenCode is already installed."
        return
    }

    if (Test-Command "choco") {
        Write-Host "Installing OpenCode with Chocolatey..."

        & choco install opencode -y

        if ($LASTEXITCODE -ne 0) {
            Fail "Chocolatey failed to install OpenCode."
        }

        Refresh-Path
        return
    }

    if (Test-Command "scoop") {
        Write-Host "Installing OpenCode with Scoop..."

        & scoop install opencode

        if ($LASTEXITCODE -ne 0) {
            Fail "Scoop failed to install OpenCode."
        }

        Refresh-Path
        return
    }

    if (-not (Test-Command "npm")) {
        Write-Host "No Chocolatey, Scoop or npm installation was found."
        Write-Host "Installing Node.js LTS so OpenCode can be installed with npm..."

        Install-WingetPackage "OpenJS.NodeJS.LTS"
        Refresh-Path
    }

    if (-not (Test-Command "npm")) {
        Fail "npm is not available after installing Node.js."
    }

    Write-Host "Installing OpenCode with npm..."

    & npm install -g opencode-ai

    if ($LASTEXITCODE -ne 0) {
        Fail "npm failed to install OpenCode."
    }

    Refresh-Path

    if (-not (Test-Command "opencode")) {
        Fail "OpenCode was installed but the 'opencode' command is not available in the current session."
    }
}

function Activate-Configuration {
    Write-Host ""
    Write-Host "Activating configuration..."

    $BackupDir = $null

    if (Test-Path $script:ConfigDir) {
        $BackupDir = (
            "$($script:ConfigDir).backup." +
            [DateTime]::Now.ToString("yyyyMMdd-HHmmss") +
            "." +
            [Guid]::NewGuid().ToString("N").Substring(0, 8)
        )

        Move-Item `
            -Path $script:ConfigDir `
            -Destination $BackupDir
    }

    try {
        Move-Item `
            -Path $script:StagingDir `
            -Destination $script:ConfigDir

        $script:StagingDir = $null
    }
    catch {
        if (
            $BackupDir -and
            (Test-Path $BackupDir) -and
            -not (Test-Path $script:ConfigDir)
        ) {
            Move-Item `
                -Path $BackupDir `
                -Destination $script:ConfigDir
        }

        Fail "Could not activate the configuration; the previous configuration was restored."
    }

    if ($BackupDir) {
        Write-Host "Previous configuration backup: $BackupDir"
    }

    Write-Host (
        "Configuration: " +
        (Join-Path $script:ConfigDir "opencode.json")
    )
}

function Cleanup {
    if (
        $script:StagingDir -and
        (Test-Path $script:StagingDir)
    ) {
        Remove-Item `
            -Path $script:StagingDir `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

try {
    Clear-Host

    Write-Host $Banner

    Write-Host @'

OpenCode installer for Solvos

Installs three primary agents:

  solvos-ultralight - local tools only, without MCPs, LSP or skills
  solvos-standard   - documentation, persistent memory, LSP and Odoo skills
  solvos-complete   - also includes filesystem access, browser automation and subagents

Includes the Ponytail plugin globally.
Creates a fresh global OpenCode configuration and archives the existing one.

'@

    $FilesystemInput = Read-Host `
        "Existing projects directory authorized for Filesystem access (absolute path)"

    if (-not [System.IO.Path]::IsPathFullyQualified($FilesystemInput)) {
        Fail "Provide an existing absolute directory path."
    }

    if (-not (Test-Path $FilesystemInput -PathType Container)) {
        Fail "The specified directory does not exist."
    }

    $script:FilesystemRoot = (
        Resolve-Path $FilesystemInput
    ).Path

    Install-Dependencies

    Prepare-Configuration

    Install-OdooSkills

    Install-Engram

    Install-OpenCode

    Activate-Configuration

    Write-Host ""
    Write-Host "Installation completed successfully."
    Write-Host ""

    $Config = Get-Content `
        -Path (Join-Path $script:ConfigDir "opencode.json") `
        -Raw |
        ConvertFrom-Json

    Write-Host "Primary agents:"

    $Config.agent.PSObject.Properties.Name |
        ForEach-Object {
            Write-Host "  $_"
        }

    Write-Host ""
    Write-Host "Start an agent with:"
    Write-Host "  opencode --agent solvos-ultralight"
    Write-Host "  opencode --agent solvos-standard"
    Write-Host "  opencode --agent solvos-complete"

    if ($Selected -eq "complete") {
        Write-Host ""
        Write-Host "Filesystem authorized directory: $script:FilesystemRoot"
        Write-Host "Playwright: if Chrome is missing, ask Solvos to use playwright browser_install."
    }
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
    exit 1
}
finally {
    Cleanup
}
