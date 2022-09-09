Mix.install([
  {:xlsx_reader, "~> 0.5.0"},
  {:jason, "~> 1.3"}
])

defmodule TmfReferenceModel.Loader do
  @moduledoc """
  Loads the TMF Reference model workbook and extracts
  the first sheet into a list of lists.
  """

  # the xlsx_reader package always us to specifiy how to convert
  # numbers using Excel Number Formatting styles.
  # See https://support.microsoft.com/en-us/office/available-number-formats-in-excel-0afe8f52-97db-41f1-b972-4b46e9f1e8d2
  @custom_formats [
    {"##.##", :string},
    {"00.00", :string},
    {"0.0", :string},
    {"#.#", :string}
  ]

  @doc """
  Reads and parses the XLSX file that contains the TMF Reference Model.

  Returns an OOXML Package
  """
  def load(input_file_path) do
    XlsxReader.open(input_file_path, supported_custom_formats: @custom_formats)
  end
end

defmodule TmfReferenceModel.Transformer.Artifacts do
  @moduledoc """
  For the list of rows in a Worksheet, transform it
  into an elixir map.
  """

  @section_separator " : "

  @doc """
  transform/2 takes an OOXML package and sheet to parse the TMF Reference model
  from and converts it into an Elixir map.
  """
  def transform(package, sheet) do
    with {:ok, rows} <- XlsxReader.sheet(package, sheet, empty_rows: false, number_type: String)
    do
      {:ok, rows |> transform_rows()}
    end
  end

  defp transform_rows(rows) when is_list(rows) do
    rows
    |> parse_header_rows()
    |> transform_artifacts()
  end

  defp parse_header_rows(rows) do
    # There are 3 "header" type rows:
    #   The first is Sheet Metadata
    #   The second and third are used to describe each artifact
    [title_row, headers_a, headers_b | rows] = rows

    %{
      metadata: title_row |> parse_metadata(),
      headers: parse_headers_to_artifact_keys(headers_a, headers_b),
      rows: rows
    }
  end

  # This parses for the first row of the spreadsheet to get document metadata info
  defp parse_metadata([document_title | additional_metadata] = _row_a) do
    ref_model_version =
      additional_metadata
      |> Enum.find(&String.contains?(&1, "Version"))
      |> String.replace("Version", "")
      |> String.trim()

    # xlsx_reader will have parsed the cell into a Date struct
    # assuming Excel automatically formatted it.
    ref_model_date =
      additional_metadata
      |> Enum.find(&is_struct(&1, Date))
      |> to_string()

    title = document_title |> String.trim()

    %{
      # :_generation_timestamp indicates when this script was run,
      # and thus when the output was generated
      :_generation_timestamp => DateTime.utc_now() |> DateTime.to_string(),
      title: title,
      version: ref_model_version,
      version_date: ref_model_date
    }
  end

  # this transforms the rows of each spreadsheet into an Elixir Map,
  # where each key matches a header value, and the value is data
  # from each individual artifact.
  defp transform_artifacts(%{metadata: metadata, headers: headers, rows: rows}) do
    artifacts =
      rows
      |> Enum.map(fn r ->
        # Combine the headers (artifact map keys] with the data from this row
        {_, artifact} =
          Enum.zip(headers, r)
          # next, build a map with 1 or more nested maps in it from the list of tuples from zip/2
          |> Enum.map_reduce(%{}, fn {k, v}, acc ->
            # Preprocessing of string before storing it in the output
            value =
              v
              |> special_conversion_hack()
              |> split_string_with_multiple_lines()

            # Search for Section headers (from the headers) to create sub maps
            k
            |> has_section_marker?()
            |> case do
              true ->
                # Need to split key into section/header
                {true, add_section_to_artifact(acc, k, value)}

              false ->
                {true, acc |> Map.put(k, value)}
            end
          end)

        artifact
      end)

    %{metadata: metadata, artifacts: artifacts}
  end

  # If any string has "\r\n" and multiple lines of strings,
  # Return a list instead of a string.
  # Also trims the strings to remove white space
  defp split_string_with_multiple_lines(str) when is_binary(str) do
    str
    |> String.split("\r\n")
    |> Enum.reject(fn s -> s == "" end)
    |> case do
      # return the only element in the list
      [any] -> any |> String.trim()
      # return list
      any -> any |> Enum.map(&String.trim/1)
    end
  end

  # Value received in `other` is not a binary (string), do just return
  # it instead of doing String processing
  defp split_string_with_multiple_lines(other), do: other

  # Handle unexpected formatting in a given XLSX version of the reference model
  # These numbers are actually in the spreadsheet, but due to Number Formatting
  # options, they are shown as the shortened versions.
  #
  # So these functions exist to revert the floating point numbers
  # back to what the user sees.
  defp special_conversion_hack("2.2000000000000002"), do: "2.2"
  defp special_conversion_hack("2.0099999999999998"), do: "2.01"
  defp special_conversion_hack("10.050000000000001"), do: "10.05"
  defp special_conversion_hack(any), do: any

  # There are 2 header rows, we need to combine them to handle
  # sub sections and merged cells. This addresses key overlap.
  # For example, "Sponsor Document" falls under:
  #  1. TMF Artifacts (Non-device)
  #  2. TMF Artifacts (Device)
  # Later, The transform_artifacts function is left to decide how to
  # created nested maps in the outputted map
  defp parse_headers_to_artifact_keys(headers_a, headers_b) do
    {_, headers} =
      Enum.zip_reduce(
        headers_a,
        headers_b,
        {"", []},
        fn a, b, {section, acc} ->
          {s, h} = combine_header_rows(a, b, section)

          # add header to accumulator list
          {s, [acc | [h |> String.replace("\r\n", " ") |> String.trim()]]}
        end
      )

    headers
    |> List.flatten()
  end

  # built an Artifact key by combining Rows A and B, optionally
  # inserting a "Section" header, ie a value from row A, but in
  # a previous column.
  defp combine_header_rows(a, b, section)
  defp combine_header_rows(a, "", _), do: {"", a}
  defp combine_header_rows("", b, ""), do: {"", b}
  defp combine_header_rows("", b, section), do: {"", concat_section_header(section, b)}
  defp combine_header_rows(a, b, ""), do: {a, concat_section_header(a, b)}

  # Build a string from 2 values
  defp concat_section_header(section, header) do
    Enum.join([section, header], @section_separator)
  end

  # Split string into a 2 element list
  defp split_key_to_section_and_header(key) do
    String.split(key, @section_separator, trim: true, parts: 2)
  end

  # Return true if the string is an output of concat_section_header/2
  defp has_section_marker?(str), do: String.contains?(str, @section_separator)

  # creates a new map within the top level artifact that corresponds
  # to a section from one of the 2 header rows in the spreadsheet.
  defp add_section_to_artifact(artifact, key, value) do
    # split key into section/header
    [section, header] = split_key_to_section_and_header(key)

    {_, new_artifact} =
      artifact
      |> Map.get_and_update(section, fn
        current_value when is_nil(current_value) ->
          {current_value, Map.new([{header, value}])}

        current_value ->
          {current_value, current_value |> Map.put(header, value)}
      end)

    new_artifact
  end
end

defmodule TmfReferenceModel.Transformer.Glossary do

  def transform(package, sheet) do
    with {:ok, rows} <- XlsxReader.sheet(package, sheet, empty_rows: false, number_type: String)
    do
      {:ok, rows |> transform_rows()}
    end
  end

  def transform_rows(rows) do
    rows
    |> Enum.reject(fn [key | _] ->
      key
      |> String.trim()
      |> case do
        "Abbreviation" -> true
        "Zone" -> true
        "Item" -> true
        _  -> false
      end
    end)
    |> Enum.map_reduce([], fn row, acc ->
      row
      |> parse()
      |> case do
       {:merged, definition} ->
          # The spreadsheet may use 2 cells to define an item.
          # when this happens, the "key" value is empty, but there is still a "value".
          # parse/1 will notice this, and return a :merged atom
          # to tell this function to look back into the accumulator for the last item
          # added, and replace that value.

          #TODO: make this special case handling cleaner
          [{key, value} | _] = acc

          {nil, acc |> List.replace_at(0, {key, value <> " " <> definition})}

        any -> {nil, [any | acc]}
      end
    end)
    |> then(fn {_, list} -> list end)
    |> List.flatten()
    |> Enum.into(%{})
  end

  defp parse(["", value | _]) do
    {:merged, value |> String.trim()}
  end

  defp parse([key, value | _]) do
    {key |> String.trim(), value |> String.trim()}
  end
end

defmodule TmfReferenceModel.Encoder.Json do
  @moduledoc """
  For the output of the Transformer module, convert the map
  into a JSON representation where each Artifact is part of a flat list.
  """

  @doc """
  Given an Elixir Map, with `:metadata` and `:artifacts` keys,
  convert it into it's JSON representation.
  """
  def encode(%{reference_model: %{metadata: metadata, artifacts: artifacts}, glossary: glossary}) do
    {:ok,
      %{
        :_metadata => metadata,
        artifacts: %{
          :_count => artifacts |> Enum.count(),
          items: artifacts
        },
        glossary: glossary
      }
      |> Jason.encode!(pretty: true)
    }
  end

  def encode(_), do: {:error, "missing metadata and artifact transformations"}

  @doc """
  Encodes the given `artifacts` into JSON using `encode/1

  """
  def encode_and_write(artifacts, input_file_name) do
    with {:ok, json} <- encode(artifacts)
    do
      output_file = input_file_name |> String.replace(".xlsx", ".json")
      IO.puts("JSON Output written to: #{output_file}")
      File.write(output_file, json)
    else
      {:error, message} = err ->
        IO.puts("JSON Encoder: Error: #{message}")
        err
    end
  end
end

defmodule TmfReferenceModel.Main do
  @moduledoc """
  Main entry point to the script.

  Reads in the TMF Reference Model as an Excel Spreadsheet with an .xlsx extension.

  Outputs a JSON file where each artifact is an element in a list (ie flat, not a tree).
  """

  alias TmfReferenceModel.Loader
  alias TmfReferenceModel.Transformer.{Artifacts, Glossary}
  alias TmfReferenceModel.Encoder.{Json}

  def main() do
    # TODO: take inputs
    input_file = "Version-3.2.1-TMF-Reference-Model-v01-Mar-2021.xlsx"
    artifact_sheet = "Ver 3.2.1 Clean"
    glossary_sheet = "Instructions and Glossary"

    with {:ok, package} <- Loader.load(input_file),
         {:ok, artifacts} <- Artifacts.transform(package, artifact_sheet),
         {:ok, glossary} <- Glossary.transform(package, glossary_sheet)
    do
      %{
        reference_model: artifacts,
        glossary: glossary
      }
      |> tap(&Json.encode_and_write(&1, input_file))
    else
      {:error, message} -> IO.puts("Error: #{message}")
    end
  end
end

TmfReferenceModel.Main.main()
