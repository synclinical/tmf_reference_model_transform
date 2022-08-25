# tmf_reference_model_transform

** NOTE: this package is in active development, and the generated output is subject to change until v1.0.0

Utility to transform the [Trial Master File Reference Model](https://tmfrefmodel.com/) into something easier to parse by software.

At time of release the currently supported transformations are:

1. JSON

## Downloads

To download the latest version of the generated file(s), go to the [Releases page](https://github.com/synclinical/tmf_reference_model_transform/releases)

## Contributing

See the [contributing guide](CONTRIBUTING.md) for instructions on how to get started with this 
project.

### Local Development
The script used to build the output is an Elixir [mix.install](https://hexdocs.pm/mix/1.13.4/Mix.html#install/2) script. There are many options to run the script locally, but 2 common options are discussed.

#### ASDF

Using the [asdf](tool), you can automatically install the versions in `.tool-versions` with:

```bash
git clone git@github.com:synclinical/tmf_reference_model_transform.git
cd tmf_reference_model_transform
asdf install
elixir tmf-transform.exs
```

#### Docker

A quick and easy way to run the script in a docker container is with this one liner:

```bash
docker run --rm -it --volume=`pwd`:/usr/src/myapp -w /usr/src/myapp elixir:alpine elixir tmf-transform.exs
# ... docker may pull the image down
# You'll be prompted to run `mix local.hex`:
Could not find Hex, which is needed to build dependency :xlsx_reader
Shall I install Hex? (if running non-interactively, use "mix local.hex --force") [Yn]
# Enter `Y`, then the script will automatically run
```
