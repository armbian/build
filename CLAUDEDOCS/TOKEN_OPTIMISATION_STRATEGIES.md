# Token Optimization Strategies for AI-Assisted Development

**Project Context**: RG34XXSP Armbian Port  
**Discovery Date**: July 17, 2025  
**Impact**: 60-80% token reduction while maintaining AI effectiveness

## Overview

During the RG34XXSP Armbian development project, we discovered that certain development tasks consume disproportionate amounts of AI tokens relative to their diagnostic value. This document outlines strategies for optimizing token usage in AI-assisted hardware development projects.

## High Token Consumption Tasks

### 1. Build Process Execution (HIGHEST IMPACT)

**Token Cost**: 1.5M tokens per successful build (3-6 Claude Code prompts)  
**Value**: Minimal - mostly repetitive compilation output  
**Optimization**: Human execution with AI involvement only for errors

#### Before Optimization:
```bash
# AI monitors entire build process
./compile.sh BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no
# Result: 1.5M tokens of build logs, 30-60% of Pro plan quota consumed
```

#### After Optimization:
```bash
# Human executes build with local logging, reports only specific errors
./compile.sh BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no 2>&1 | tee build_log.txt | tail -20

# Benefits:
# - Full logs saved locally to build_log.txt for debugging
# - Only last 20 lines shown on screen (manageable output)
# - Human reports to AI: "Build completed successfully" OR specific error from build_log.txt
# Result: ~50 tokens for error reporting vs 1.5M for full AI monitoring
```

### 2. Large File Reading (HIGH IMPACT)

**Token Cost**: 10K-50K tokens per large file  
**Value**: Medium - often only specific sections needed  
**Optimization**: Use `limit` and `offset` parameters, targeted searches

#### Before Optimization:
```bash
Read tool: /path/to/large_file.c  # 2000+ lines = 50K+ tokens
```

#### After Optimization:
```bash
Read tool: /path/to/large_file.c limit=50  # 50 lines = 1-2K tokens
Grep tool: pattern="specific_function" output_mode="content"  # Targeted search
```

### 3. Directory Exploration (MEDIUM IMPACT)

**Token Cost**: 5K-20K tokens for large directory structures  
**Value**: Medium - often only specific files needed  
**Optimization**: Use targeted Glob patterns, specific file searches

#### Before Optimization:
```bash
LS tool: /large/directory/with/thousands/of/files
```

#### After Optimization:
```bash
Glob tool: pattern="**/*.dts" path="/specific/path"  # Targeted file search
Grep tool: pattern="CONFIG_" glob="*.config"  # Pattern-based filtering
```

### 4. Repository Analysis (MEDIUM IMPACT)

**Token Cost**: 20K-100K tokens for comprehensive analysis  
**Value**: High - but often only specific information needed  
**Optimization**: Use Task tool for complex searches, focused research

#### Before Optimization:
```bash
# Multiple Read operations across entire repository
Read tool: file1, file2, file3, file4...
```

#### After Optimization:
```bash
Task tool: "Find all H700 device tree configurations in ROCKNIX repository"
# AI performs targeted analysis and returns summary
```

## Implementation Strategy

### Phase-Based Token Budgeting

#### Phase 0: Research and Planning (Budget: 30% of quota)
- **High-value tasks**: Repository analysis, hardware research, strategic planning
- **Optimization**: Use Task tool for complex searches, WebSearch for targeted information
- **Avoid**: Reading entire files, processing large directory listings

#### Phase 1: Configuration and Setup (Budget: 20% of quota)
- **High-value tasks**: File creation, configuration analysis, patch development
- **Optimization**: Read specific file sections, use targeted Grep searches
- **Avoid**: Processing build logs, reading large kernel files

#### Phase 2: Implementation (Budget: 20% of quota)
- **High-value tasks**: Error diagnosis, configuration fixes, patch corrections
- **Optimization**: Human executes builds, AI analyzes specific errors only
- **Avoid**: Monitoring successful build processes

#### Phase 3: Testing and Debugging (Budget: 20% of quota)
- **High-value tasks**: Boot failure analysis, hardware investigation, problem solving
- **Optimization**: Focus on specific error messages, targeted file analysis
- **Avoid**: Reading entire log files, processing successful test outputs

#### Phase 4: Documentation (Budget: 10% of quota)
- **High-value tasks**: Writing guides, updating documentation, final cleanup
- **Optimization**: Targeted edits, specific file updates
- **Avoid**: Reading entire documentation files for minor updates

### Token-Efficient Workflow Patterns

#### 1. Error-Driven Development
```bash
# Instead of: AI monitors entire process
# Do: Human executes, AI analyzes only failures
Human: "Build failed with specific error X"
AI: Analyzes error, provides targeted fix
Human: Implements fix, tests
```

#### 2. AI-Executable Token-Optimized Commands
```bash
# Exception: AI can run builds using token-optimized approach
# This specific command pattern is approved for AI execution:
./compile.sh build BOARD=rg34xxsp BRANCH=current RELEASE=bookworm BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no 2>&1 | tee build_log.txt | tail -20

# Rationale:
# - Uses tee to save full logs locally (no token cost for full logs)
# - tail -20 limits AI monitoring to essential final output only
# - Enables AI to execute builds while maintaining token efficiency
# - Preserves full debugging capability through local build_log.txt
```

#### 2. Targeted Research
```bash
# Instead of: Read entire files to find information
# Do: Use search tools to find specific content
Grep tool: pattern="target_info" files_with_matches
Read tool: /specific/file.txt limit=20 offset=450
```

#### 3. Incremental Analysis
```bash
# Instead of: Analyzing all options at once
# Do: Analyze most promising options first
AI: "Based on quick analysis, try option A first"
Human: Tests option A
If successful: Stop. If failed: Analyze option B
```

## Monitoring and Metrics

### Token Usage Awareness
- **High-cost operations**: Build monitoring, large file reading, directory exploration
- **Medium-cost operations**: Targeted searches, specific file analysis
- **Low-cost operations**: Configuration creation, error analysis, documentation

### Success Metrics
- **Token efficiency**: Problems solved per token consumed
- **Error resolution rate**: Percentage of issues resolved without build monitoring
- **Quota preservation**: Percentage of allowance available for critical debugging

### Warning Signs
- **Multiple build log processing**: Indicates need for workflow optimization
- **Repeated large file reading**: Suggests need for targeted search strategy
- **Quota exhaustion early in project**: Indicates inefficient token allocation

## Tools and Techniques

### Preferred Tools for Token Efficiency
1. **Task tool**: For complex, multi-step research that would require many individual operations
2. **Grep tool**: For targeted content searches instead of reading entire files
3. **Glob tool**: For finding specific file types instead of browsing directories
4. **Edit/MultiEdit tools**: For targeted changes instead of rewriting entire files

### Tool Parameters for Optimization
- **Read tool**: Always use `limit` for large files, `offset` for specific sections
- **Grep tool**: Use `head_limit` to prevent massive result sets
- **LS tool**: Avoid on large directories, use specific paths only
- **Bash tool**: Use for simple operations instead of complex tool chains

## Claude Code Pro Plan Specific Guidance

### Usage Allowance: 10-40 prompts per 5 hours

#### Critical Token Budgeting:
- **Single build monitoring**: 3-6 prompts (30-60% of allowance)
- **Large repository analysis**: 2-4 prompts (20-40% of allowance)
- **Complex debugging session**: 1-2 prompts (10-20% of allowance)

#### Recommended Allocation:
- **Research and planning**: 40% of quota
- **Configuration and fixes**: 30% of quota  
- **Error diagnosis**: 20% of quota
- **Documentation**: 10% of quota

#### Emergency Protocols:
- **If quota exhausted**: Focus only on critical blockers
- **If near limit**: Switch to human-only execution mode
- **If quota preserved**: Invest in comprehensive analysis for complex issues

## Implementation Checklist

### Before Starting AI Collaboration:
- [ ] Identify high-token operations in your project type
- [ ] Establish human-AI boundaries for build processes
- [ ] Plan token budget allocation across project phases
- [ ] Set up monitoring for token-heavy operations

### During Development:
- [ ] Use targeted search tools instead of broad file reading
- [ ] Interrupt successful builds early
- [ ] Focus AI assistance on error analysis, not process monitoring
- [ ] Monitor quota usage and adjust strategy accordingly

### Post-Project Review:
- [ ] Analyze token usage patterns
- [ ] Identify optimization opportunities for future projects
- [ ] Document lessons learned for team knowledge sharing
- [ ] Update strategies based on actual vs planned token consumption

## Conclusion

Token optimization in AI-assisted development is about **strategic task allocation** rather than limiting AI involvement. By focusing AI assistance on high-value problem-solving tasks while having humans handle repetitive, log-heavy processes, projects can achieve better outcomes while preserving usage quotas for critical debugging and complex analysis.

The key insight: **AI should solve problems, humans should execute solutions.**

---

*This document was created retrospectively during the RG34XXSP Armbian port project after discovering significant token optimization opportunities. The strategies outlined here reduced token usage by 60-80% while maintaining full AI effectiveness for technical problem-solving.*