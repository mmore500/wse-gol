# wse-async-ga

[![CI](https://github.com/mmore500/wse-async-ga/actions/workflows/ci.yaml/badge.svg)](https://github.com/mmore500/wse-async-ga/actions/workflows/ci.yaml)
[![GitHub stars](https://img.shields.io/github/stars/mmore500/wse-async-ga.svg?style=flat-square&logo=github&label=Stars&logoColor=white)](https://github.com/mmore500/wse-async-ga)

Development work for agent-based evolution/epidemiological modeling on the Cerebras Wafer-scale Engine (WSE) hardware.
Incoprorates [hereditary stratigraphy](https://github.com/mmore500/hstrat) methodology for distributed tracking of agent phylogenies.

Requires [Cerebras SDK](https://www.cerebras.net/developers/sdk-request/), available through invitation.
Library CSL code targets compatibility with Cerebras SDK v1.X releases. As of October 2025, library code is tested against Cerebras SDK v1.4.0.

## Contents

- `cerebraslib`: port of `hsurf` algorithms to Cerebras Software Language (CSL) as well other supporting materials for WSE kernels
- `kernel-test-cerebraslib`: uses Cerebras WSE hardware simulator to run unit tests on `cerebraslib` components
- `kernel-async-ga`: general purpose framework for decentralized, island-model genetic algorithm across WSE Processing Elements (PEs), with configurably-sized agent genomes, customizable mutation operator, and customizable fitness function; includes scripts to run on Cerebras WSE hardware simulator
- `pylib`: Python support code for data analysis

## Installation and Running

See our [Continuous Integration config](https://github.com/mmore500/wse-async-ga/blob/master/.github/workflows/ci.yaml) for detailed instructions on installing dependencies and running project components.

Note that the `test-csl` continuous integration components do not run within the scope of the public-facing `wse-async-ga` repository in order to protect Cerebras' intellectual property.

## Citing

If wse-async-ga contributes to a scientific publication, please cite it as

> Matthew Andres Moreno and Connor Yang. (2024). mmore500/wse-async-ga

```bibtex
@software{moreno2024wse,
  author = {Matthew Andres Moreno and Connor Yang},
  title = {mmore500/wse-async-ga},
  month = dec,
  year = 2024,
}
```

Consider also citing [hsurf](https://github.com/mmore500/hstrat-surface-concept/blob/master/README.md#citing), [hstrat](https://hstrat.readthedocs.io/en/stable/citing.html), and downstream.
And don't forget to leave a [star on GitHub](https://github.com/mmore500/pecking/stargazers)!

## Contact

Matthew Andres Moreno
<morenoma@umich.edu>
