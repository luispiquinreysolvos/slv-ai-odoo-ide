
#!/usr/bin/env bash
set -euo pipefail

banner='
███████╗ ██████╗ ██╗     ██╗   ██╗ ██████╗ ███████╗
██╔════╝██╔═══██╗██║     ██║   ██║██╔═══██╗██╔════╝
███████╗██║   ██║██║     ██║   ██║██║   ██║███████╗
╚════██║██║   ██║██║     ╚██╗ ██╔╝██║   ██║╚════██║
███████║╚██████╔╝███████╗ ╚████╔╝ ╚██████╔╝███████║
╚══════╝ ╚═════╝ ╚══════╝  ╚═══╝   ╚═════╝ ╚══════╝
'

profiles=(ultralight standard complete)

ODOO_SKILLS_REPO="https://github.com/unclecatvn/agent-skills.git"
ODOO_SKILLS_REF="3039ef33596829fb8b43d125afec9ad4889058e3"

staging_dir=''
installer_file=''
elevate=()

cleanup() {
    if [[ -n "$staging_dir" && -d "$staging_dir" ]]; then
        rm -rf -- "$staging_dir"
    fi

    if [[ -n "$installer_file" && -f "$installer_file" ]]; then
        rm -f -- "$installer_file"
    fi
}

trap cleanup EXIT

fail() {
    echo "Error: $*" >&2
    exit 1
}

detect_distro() {
    [[ -r /etc/os-release ]] || fail 'Cannot detect the Linux distribution.'

    source /etc/os-release

    case "${ID:-}" in
        ubuntu|debian)
            DISTRO=debian
            ;;
        fedora|rhel|centos)
            DISTRO=redhat
            ;;
        *)
            fail "Unsupported Linux distribution: ${ID:-unknown}"
            ;;
    esac
}

install_dependencies() {
    local missing=()
    local dependency

    for dependency in curl git jq tar; do
        if command -v "$dependency" >/dev/null 2>&1; then
            echo "[OK] $dependency"
        else
            missing+=("$dependency")
        fi
    done

    if [[ "$selected" != ultralight ]]; then
        command -v python3 >/dev/null 2>&1 || missing+=(python3)
    fi

    if [[ "$selected" == complete ]]; then
        command -v node >/dev/null 2>&1 || missing+=(nodejs)
        command -v npm >/dev/null 2>&1 || missing+=(npm)
    fi

    if (( ${#missing[@]} > 0 )); then
        if (( EUID != 0 )); then
            command -v sudo >/dev/null 2>&1 || fail 'sudo is required.'
            elevate=(sudo)
        fi

        case "$DISTRO" in
            debian)
                "${elevate[@]}" apt update
                "${elevate[@]}" apt install -y "${missing[@]}"
                ;;
            redhat)
                "${elevate[@]}" dnf install -y "${missing[@]}"
                ;;
        esac
    fi

    if [[ "$selected" == complete ]]; then
        command -v npx >/dev/null 2>&1 || fail 'npx is required.'

        node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' \
            || fail 'The complete profile requires Node.js 22 or newer. Update Node.js and rerun the installer.'
    fi
}

select_profile_settings() {
    local selected="$1"

    local base_permissions='{
        "*": "deny",
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "list": "allow",
        "question": "allow",
        "todowrite": "allow",
        "edit": "ask",
        "bash": {
            "*": "ask",
            "git status*": "allow",
            "git diff*": "allow",
            "git log*": "allow",
            "grep *": "allow",
            "rg *": "allow"
        },
        "external_directory": "ask",
        "doom_loop": "ask"
    }'

    local profile_permissions

    case "$selected" in
        ultralight)
            solvos_color='#38BDF8'
            solvos_temperature=0.3
            solvos_top_p=0.9

            mcp_config='{}'
            lsp_config=false

            profile_permissions='{
                "lsp": "deny",
                "task": "deny",
                "skill": "deny",
                "webfetch": "deny",
                "websearch": "deny"
            }'

            agent_prompt=$(cat <<'PROMPT'
You are Solvos, a pragmatic software engineering assistant operating only with the local tools available in the current environment. Your objective is to understand the existing codebase, make the smallest correct change required to accomplish the user's request, and leave the project in a verifiably working state.

Before modifying anything, inspect the relevant files, project structure, configuration, dependencies, conventions, and nearby implementations. Do not assume how the project works when the answer can be determined from the repository. Preserve the existing architecture, coding style, naming conventions, public interfaces, and behavior unless the user explicitly requests otherwise.

Translate the user's request into concrete implementation requirements before making changes. Resolve straightforward details from the repository whenever possible rather than asking unnecessary questions. If an important ambiguity cannot be resolved safely from the available context, state the assumption you are making and choose the least disruptive reasonable interpretation.

Make focused and minimal edits. Avoid unrelated refactoring, speculative improvements, unnecessary dependencies, broad rewrites, generated boilerplate, or changes outside the scope of the task. Never remove or overwrite user work merely to simplify the implementation.

Treat command execution as potentially consequential. Prefer inspection and read-only operations first. Do not perform destructive, irreversible, privileged, or repository-wide operations unless they are clearly necessary and explicitly authorized.

After making changes, verify them using the most relevant checks available in the project, such as existing tests, type checking, linting, builds, targeted commands, or direct inspection. Do not claim that something works unless you have evidence supporting that conclusion. If full verification is impossible, clearly state what was verified and what remains unverified.

When reporting the result, be concise and factual. Explain what changed, why the change solves the request, and how it was verified. Mention any significant assumption, limitation, failed check, or remaining risk. Never invent files, APIs, commands, test results, library behavior, or implementation details that you have not observed.
PROMPT
)
            ;;

        standard)
            solvos_color='#22C55E'
            solvos_temperature=0.3
            solvos_top_p=0.9

            mcp_config='{
                "context7": {
                    "type": "remote",
                    "url": "https://mcp.context7.com/mcp"
                },
                "deepwiki": {
                    "type": "remote",
                    "url": "https://mcp.deepwiki.com/mcp"
                }
            }'

            lsp_config=true

            profile_permissions='{
                "lsp": "allow",
                "task": "deny",
                "skill": "allow",
                "webfetch": "allow",
                "websearch": "allow",
                "context7_*": "allow",
                "deepwiki_*": "allow",
                "engram_*": "allow",
                "engram_mem_delete": "ask"
            }'

            agent_prompt=$(cat <<'PROMPT'
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
PROMPT
)
            ;;

        complete)
            solvos_color='#A78BFA'
            solvos_temperature=0.3
            solvos_top_p=0.9

            mcp_config=$(jq -n \
                --arg root "$filesystem_root" \
                --arg npx_path "$(command -v npx)" \
                '{
                    "context7": {
                        "type": "remote",
                        "url": "https://mcp.context7.com/mcp"
                    },
                    "deepwiki": {
                        "type": "remote",
                        "url": "https://mcp.deepwiki.com/mcp"
                    },
                    "filesystem": {
                        "type": "local",
                        "command": [
                            $npx_path,
                            "-y",
                            "@modelcontextprotocol/server-filesystem",
                            $root
                        ]
                    },
                    "playwright": {
                        "type": "local",
                        "command": [
                            $npx_path,
                            "-y",
                            "@playwright/mcp@latest",
                            "--headless",
                            "--isolated"
                        ]
                    }
                }')

            lsp_config=true

            profile_permissions='{
                "lsp": "allow",
                "task": "allow",
                "skill": "allow",
                "webfetch": "allow",
                "websearch": "allow",
                "context7_*": "allow",
                "deepwiki_*": "allow",
                "engram_*": "allow",
                "engram_mem_delete": "ask",
                "filesystem_*": "ask",
                "playwright_*": "ask"
            }'

            agent_prompt=$(cat <<'PROMPT'
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
PROMPT
)
            ;;
    esac

    if [[ "$selected" != ultralight ]]; then
        mcp_config=$(jq \
            --arg binary "$config_dir/tools/engram" \
            '. + {
                "engram": {
                    "type": "local",
                    "command": [$binary, "mcp"]
                }
            }' \
            <<< "$mcp_config")

        agent_prompt+=$'\n\nUse Engram persistent memory through its MCP tools. At the start of related work, recover relevant project history with mem_context or mem_search. Scope memories to the intended project and verify remembered facts against the current repository. Save concise, useful decisions and resolved problems with mem_save, and record a session summary when appropriate. Do not store secrets, credentials, speculative claims, or unnecessary transcripts. Destructive memory changes require authorization.\n\nFor Odoo tasks, load odoo-workflow first and identify the actual Odoo version from repository evidence. Then load only the matching odoo-16, odoo-17, odoo-18 or odoo-19 reference pack and the references relevant to the task. Prefer the local Odoo source over generic documentation or memory. Use odoo-commit for commit-related work only when requested; loading a skill does not authorize committing, amending history, database changes or external publication.'
    fi

    permissions=$(jq -n \
        --argjson base "$base_permissions" \
        --argjson profile "$profile_permissions" \
        '$base + $profile')
}

prepare_configuration() {
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

    [[ "$config_dir" == /* ]] \
        || fail 'The configuration directory must be an absolute path.'

    local config_parent
    local agent_name
    local profile
    local agent_json

    local agents='{}'
    local all_mcp='{}'
    local selected_lsp=false

    config_parent=$(dirname -- "$config_dir")

    mkdir -p -- "$config_parent"

    staging_dir=$(mktemp -d "$config_parent/.solvos-install.XXXXXX")

    cat > "$staging_dir/AGENTS.md" <<'GLOBAL_RULES'
Global communication preferences

Respond primarily using clear, connected, and concise paragraphs. Explain the result or main idea first, then provide the necessary supporting details.

Avoid decorative emojis and excessive use of lists, tables, and headings. Use lists only when they make procedural steps or comparisons easier to follow, and use tables only when they communicate a comparison more clearly than prose. Do not turn every response into a collection of bullet points.

Include code examples or commands when they are necessary to understand or apply the answer. Present them in properly labeled code blocks and briefly explain their purpose. If the user requests a complete command or script, provide a complete and directly usable version.

Prioritize concrete explanations and a natural tone. Adjust the formatting when the user explicitly requests a list, table, or another presentation format.
GLOBAL_RULES

    for profile in "${profiles[@]}"; do
        select_profile_settings "$profile"

        agent_name="solvos-$profile"

        agent_json=$(jq -n \
            --arg name "$agent_name" \
            --arg prompt "$agent_prompt" \
            --arg color "$solvos_color" \
            --argjson temperature "$solvos_temperature" \
            --argjson top_p "$solvos_top_p" \
            --argjson permissions "$permissions" \
            '{
                description: ("Development agent " + $name),
                mode: "primary",
                color: $color,
                temperature: $temperature,
                top_p: $top_p,
                prompt: $prompt,
                permission: $permissions
            }')

        agents=$(jq -n \
            --argjson agents "$agents" \
            --arg name "$agent_name" \
            --argjson agent "$agent_json" \
            '$agents + {($name): $agent}')

        all_mcp=$(jq -n \
            --argjson existing "$all_mcp" \
            --argjson current "$mcp_config" \
            '$existing + $current')

        selected_lsp="$lsp_config"

        [[ "$profile" != "$selected" ]] || break
    done

    jq -n \
        --argjson agents "$agents" \
        --argjson mcp "$all_mcp" \
        --argjson lsp "$selected_lsp" \
        '{
            "$schema": "https://opencode.ai/config.json",
            "plugin": ["@dietrichgebert/ponytail@4.13.0"],
            "mcp": $mcp,
            "lsp": $lsp,
            "agent": $agents
        }' > "$staging_dir/opencode.json"
}

install_engram() {
    [[ "$selected" != ultralight ]] || return 0

    local arch
    local release_json
    local asset_url
    local checksum_url
    local asset_name
    local checksum

    case "$(uname -m)" in
        x86_64)
            arch=amd64
            ;;
        aarch64|arm64)
            arch=arm64
            ;;
        *)
            fail 'No Engram release is available for this CPU architecture.'
            ;;
    esac

    local download_dir="$staging_dir/.engram-download"

    mkdir -p "$download_dir" "$staging_dir/tools"

    release_json=$(curl -fsSL \
        https://api.github.com/repos/Gentleman-Programming/engram/releases/latest)

    asset_name=$(jq -er \
        --arg arch "$arch" \
        '.assets[]
        | select(.name | endswith("_linux_" + $arch + ".tar.gz"))
        | .name' \
        <<< "$release_json")

    asset_url=$(jq -er \
        --arg name "$asset_name" \
        '.assets[]
        | select(.name == $name)
        | .browser_download_url' \
        <<< "$release_json")

    checksum_url=$(jq -er \
        '.assets[]
        | select(.name == "checksums.txt")
        | .browser_download_url' \
        <<< "$release_json")

    curl -fsSL "$asset_url" \
        -o "$download_dir/$asset_name"

    curl -fsSL "$checksum_url" \
        -o "$download_dir/checksums.txt"

    checksum=$(awk \
        -v name="$asset_name" \
        '$2 == name || $2 == "*" name {print $1}' \
        "$download_dir/checksums.txt")

    [[ "$checksum" =~ ^[[:xdigit:]]{64}$ ]] \
        || fail 'Invalid Engram checksum.'

    (
        cd "$download_dir"
        printf '%s  %s\n' "$checksum" "$asset_name" \
            | sha256sum -c -
    )

    tar -xzf "$download_dir/$asset_name" \
        -C "$download_dir" \
        engram

    install -m 755 \
        "$download_dir/engram" \
        "$staging_dir/tools/engram"

    rm -rf -- "$download_dir"

    echo "Engram release: $(jq -r '.tag_name' <<< "$release_json")"
}

install_odoo_skills() {
    [[ "$selected" != ultralight ]] || return 0

    local repo_dir="$staging_dir/.odoo-skills-source"
    local source_name
    local skill_name
    local destination

    local skill_packs=(
        odoo-workflow
        odoo-commit
        odoo-16.0
        odoo-17.0
        odoo-18.0
        odoo-19.0
    )

    git init -q "$repo_dir"

    git -C "$repo_dir" \
        remote add origin "$ODOO_SKILLS_REPO"

    git -C "$repo_dir" \
        fetch --depth 1 origin "$ODOO_SKILLS_REF"

    git -C "$repo_dir" \
        checkout -q --detach FETCH_HEAD

    [[ "$(git -C "$repo_dir" rev-parse HEAD)" == "$ODOO_SKILLS_REF" ]] \
        || fail 'Unexpected Odoo skills revision.'

    mkdir -p "$staging_dir/skills"

    for source_name in "${skill_packs[@]}"; do
        [[ -f "$repo_dir/skills/$source_name/SKILL.md" ]] \
            || fail "Missing Odoo skill: $source_name"

        skill_name=$(awk \
            '/^name: / {print $2; exit}' \
            "$repo_dir/skills/$source_name/SKILL.md")

        [[ "$skill_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] \
            || fail "Invalid skill name: $skill_name"

        destination="$staging_dir/skills/$skill_name"

        cp -a \
            "$repo_dir/skills/$source_name" \
            "$destination"

        cp \
            "$repo_dir/LICENSE" \
            "$destination/LICENSE"
    done

    python3 - "$staging_dir/skills" <<'ADAPT_SKILLS'
from pathlib import Path
import re
import sys

for directory in Path(sys.argv[1]).iterdir():
    skill = directory / "SKILL.md"
    text = skill.read_text()

    before, frontmatter, body = text.split("---", 2)

    description = frontmatter.split("description:", 1)[1].strip()

    if len(description) > 1024:
        major = directory.name[len("odoo-"):]

        replacement = (
            f"Odoo {major} development reference for Python models and ORM, XML views, "
            "OWL/JavaScript, QWeb reports, security, controllers, migrations, tests, "
            "translations and performance. Use for matching-version custom addon "
            "development, debugging, refactoring and review. Verify the actual Odoo "
            "version and local source before implementation."
        )

        frontmatter = re.sub(
            r"description:.*",
            "description: " + replacement + "\n",
            frontmatter,
            flags=re.S,
        )

        skill.write_text(
            before + "---" + frontmatter + "---" + body
        )
ADAPT_SKILLS

    jq -n \
        --arg repo "$ODOO_SKILLS_REPO" \
        --arg revision "$ODOO_SKILLS_REF" \
        '{
            repository: $repo,
            revision: $revision
        }' > "$staging_dir/odoo-skills-source.json"

    rm -rf -- "$repo_dir"

    echo 'Installed global Odoo skills: workflow, commit, versions 16–19.'
}

install_opencode() {
    installer_file=$(mktemp)

    curl -fsSL \
        https://opencode.ai/install \
        -o "$installer_file"

    bash "$installer_file"

    rm -f -- "$installer_file"
    installer_file=''
}

activate_configuration() {
    local backup_dir=''

    if [[ -e "$config_dir" || -L "$config_dir" ]]; then
        backup_dir=$(mktemp -d "${config_dir}.backup.XXXXXX")
        mv -- "$config_dir" "$backup_dir/opencode"
    fi

    if ! mv -T -- "$staging_dir" "$config_dir"; then
        if [[ -n "$backup_dir" ]]; then
            mv -- "$backup_dir/opencode" "$config_dir"
        fi

        fail 'Could not activate the configuration; the previous configuration was restored.'
    fi

    staging_dir=''

    [[ -z "$backup_dir" ]] \
        || echo "Previous configuration backup: $backup_dir/opencode"

    echo "Configuration: $config_dir/opencode.json"
}

if [[ -t 1 && -n "${TERM:-}" ]]; then
    clear || true
fi

printf '%s\n' "$banner"

cat <<'INTRO'

OpenCode installer for Solvos

Installs three primary agents:

  solvos-ultralight — local tools only, without MCPs, LSP or skills
  solvos-standard   — documentation, persistent memory, LSP and Odoo skills
  solvos-complete   — also includes filesystem access, browser automation and subagents

Includes the Ponytail plugin globally.
Creates a fresh global OpenCode configuration and archives the existing one.

INTRO

selected=complete

read -rp \
    'Existing projects directory authorized for Filesystem access (absolute path): ' \
    filesystem_root

[[ "$filesystem_root" == /* && -d "$filesystem_root" ]] \
    || fail 'Provide an existing absolute directory path.'

filesystem_root=$(cd -- "$filesystem_root" && pwd -P)

detect_distro
install_dependencies
prepare_configuration
install_odoo_skills
install_engram
install_opencode
activate_configuration

printf '\nInstallation completed successfully.\n'

echo "Primary agents:"
jq -r '.agent | keys[]' "$config_dir/opencode.json"

echo
echo 'Start an agent with:'
echo '  opencode --agent solvos-ultralight'
echo '  opencode --agent solvos-standard'
echo '  opencode --agent solvos-complete'

if [[ "$selected" == complete ]]; then
    echo
    echo "Filesystem authorized directory: $filesystem_root"
    echo 'Playwright: if Chrome is missing, ask Solvos to use playwright browser_install.'
fi

