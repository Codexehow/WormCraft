# Worm Game

## Project Charter & Development Philosophy V0.1

### Purpose

Worm Game exists as an experiment in AI-assisted game development.

Unlike previous projects, the goal is not to fully design the game before implementation begins.

Instead, the project will follow an iterative cycle:

Idea → Specification → Implementation → Playtest → Audit → Expansion

The game itself will be discovered through development rather than fully planned in advance.

The role of design documents is not to predict the finished game.

The role of design documents is to preserve the rules that prevent the game from losing its identity.

------

# Core Premise

The player controls the only sapient earthworm in existence.

The worm begins life in ordinary soil.

The dirt tastes bad.

The bugs are annoying.

The worm begins manipulating its environment to improve its situation.

This process gradually escalates from soil management to ecosystem engineering, industrialization, planetary influence, and eventually space expansion.

Despite the increasing scale, the protagonist always remains the same worm.

------

# Immutable Design Pillars

These principles may not be violated without an explicit project-wide redesign.

## Pillar 1: The Player Is Always A Worm

The player never evolves into a humanoid.

The player never becomes a god.

The player never abandons the worm identity.

The player may control larger systems, colonies, organizations, or civilizations, but remains the original worm throughout the entire game.

The worm is the game's identity.

------

## Pillar 2: Technology Is Discovered, Not Unlocked

The game does not use a traditional crafting tree.

Players do not unlock predefined recipes.

Players discover materials, components, tags, and behaviors.

Technology emerges from experimentation.

The player creates solutions rather than following prescribed paths.

------

## Pillar 3: Systems Generate Content

The project should prioritize systems over handcrafted content.

Whenever possible:

Do not build 500 unique machines.

Build systems capable of generating 500 machines.

Do not build hundreds of recipes.

Build interaction rules.

Player experimentation should generate gameplay.

------

## Pillar 4: Scale Is Progression

The player begins focused on individual dirt tiles.

Over time the player's sphere of influence expands.

Possible progression:

Dirt Tile
Tunnel
Burrow
Garden
Forest
Region
Planet
Star System

The game should continuously expand the player's perspective.

Progression is measured primarily through scale.

------

## Pillar 5: Emergence Is Preferred Over Balance

Unexpected outcomes are desirable.

Players should occasionally create:

- Unintended machines
- Unexpected behaviors
- Useful accidents
- Harmful accidents
- Self-created challenges

The game should evaluate whether an outcome is interesting before evaluating whether it is perfectly balanced.

Emergent stories are a design goal.

------

# Machine Philosophy

Machines are not predefined objects.

Machines are collections of components, tags, behaviors, and constraints.

Example tags:

- Digging
- Moving
- Storing
- Growing
- Living
- Rotating
- Sharp
- Acidic
- Conductive
- Elastic

The game does not determine whether a machine matches player intent.

The game determines what the machine actually does.

Player intention is irrelevant.

Behavior is determined entirely by machine composition.

------

# Engineering Constraints

The game uses engineering-style abstractions similar to Aurora or Distant Worlds.

Machines possess:

Mass
Power Draw
Complexity
Control Requirement
Reliability

These values exist to constrain machine design and provide meaningful progression.

Research primarily increases allowable limits rather than unlocking predefined machines.

Research unlocks capability.

Players create the applications.

------

# Art Direction

Visual Style:

- 2D
- Pixel Art
- Side View

Machines should visually reflect approximate size and purpose.

Machine sprites should be selected from categorized sprite pools rather than requiring procedural sprite assembly.

The player's machine should feel visually appropriate to its role and scale.

Perfect visual accuracy is not required.

Believability is required.

------

# Development Methodology

## Phase 1: Conversational Design

Ideas originate through discussion.

Design documentation captures rules, systems, and constraints.

Documentation should remain lightweight.

Avoid excessive upfront planning.

------

## Phase 2: Vertical Slice First

Every new feature should begin with the smallest playable implementation.

Examples:

Worm movement.
Eating dirt.
Collecting stones.
Building a single machine.

Large systems should be proven before expansion.

------

## Phase 3: Audit Driven Development

Regular audits should evaluate:

- Technical debt
- Architectural stability
- Gameplay value
- System coherence

Audits are preferred over large upfront planning efforts.

------

## Phase 4: Expand What Is Fun

Features should be expanded because they create meaningful gameplay.

Features should not be expanded solely because they exist in a design document.

The game should grow from successful experiments.

------

# Scope Control Rule

No feature enters development unless it solves an existing gameplay problem.

Bad:

"Add ant politics because it sounds cool."

Good:

"Mid-game lacks strategic pressure. Ant politics creates competing factions and resource demands."

Every new system must justify its existence through gameplay value.

------

# Success Condition

Success is not creating a perfectly planned game.

Success is creating a playable, surprising, emergent game whose systems continuously generate interesting stories and problems for the player.

The project should remain flexible enough to discover ideas that were not anticipated at the start of development.