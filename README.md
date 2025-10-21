# wse-gol

[![CI](https://github.com/mmore500/wse-gol/actions/workflows/ci.yaml/badge.svg)](https://github.com/mmore500/wse-gol/actions/workflows/ci.yaml)
[![GitHub stars](https://img.shields.io/github/stars/mmore500/wse-gol.svg?style=flat-square&logo=github&label=Stars&logoColor=white)](https://github.com/mmore500/wse-gol)

Development work for agent-based evolution/epidemiological modeling on the Cerebras Wafer-scale Engine (WSE) hardware.
Incoprorates [hereditary stratigraphy](https://github.com/mmore500/hstrat) methodology for distributed tracking of agent phylogenies.

Requires [Cerebras SDK](https://www.cerebras.net/developers/sdk-request/), available through invitation.
Library CSL code targets compatibility with Cerebras SDK v1.X releases.
As of October 2025, library code is tested against Cerebras SDK v1.4.0.

## Contents

- `cerebraslib`: port of `hsurf` algorithms to Cerebras Software Language (CSL) as well other supporting materials for WSE kernels
- `kernel-test-cerebraslib`: uses Cerebras WSE hardware simulator to run unit tests on `cerebraslib` components
- `kernel-gol`: general purpose framework for decentralized, island-model genetic algorithm across WSE Processing Elements (PEs), with configurably-sized agent genomes, customizable mutation operator, and customizable fitness function; includes scripts to run on Cerebras WSE hardware simulator
- `pylib`: Python support code for data analysis

## Installation and Running

See our [Continuous Integration config](https://github.com/mmore500/wse-gol/blob/master/.github/workflows/ci.yaml) for detailed instructions on installing dependencies and running project components.

## Contact

Matthew Andres Moreno
<morenoma@umich.edu>
