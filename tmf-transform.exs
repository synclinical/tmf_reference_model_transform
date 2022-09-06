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

  Returns a list of rows for the following sheets:
    - The TMF Reference Model
    - Glossary
  """
  def load(input_file_path) do
    {:ok, package} = XlsxReader.open(input_file_path, supported_custom_formats: @custom_formats)

    [sheet | _] = XlsxReader.sheet_names(package)

    XlsxReader.sheet(package, sheet, empty_rows: false, number_type: String)
  end
end

defmodule TmfReferenceModel.Transformer do
  @moduledoc """
  For the list of rows in a Worksheet, transform it
  into an elixir map.
  """

  @section_separator " : "

  @doc """
  transform/1 takes a list of rows from the TMF Reference model spreadsheet
  and converts it into an Elixir map.
  """
  def transform(rows) when is_list(rows) do
    rows
    |> parse_header_rows()
    |> transform_artifacts()
  end

  def transform({:ok, rows}), do: transform(rows)
  def transform(any), do: IO.puts("Error loading rows: #{any}")

  defp parse_header_rows(rows) do
    [title_row, headers_a, headers_b | rows] = rows

    %{
      metadata: title_row |> parse_metadata(),
      headers: parse_headers(headers_a, headers_b),
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

    ref_model_date =
      additional_metadata
      |> Enum.find(&is_struct(&1, Date))
      |> to_string()

    title = document_title |> String.trim()

    %{
      :_generation_timestamp => DateTime.utc_now() |> DateTime.to_string(),
      title: title,
      version: ref_model_version,
      version_date: ref_model_date
    }
  end

  # There are 2 header rows, we need to combine them to handle
  # sub sections and merged cells
  defp parse_headers(headers_a, headers_b) do
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

  defp combine_header_rows(a, b, section)
  defp combine_header_rows(a, "", _), do: {"", a}
  defp combine_header_rows("", b, ""), do: {"", b}
  defp combine_header_rows("", b, section), do: {"", concat_section_header(section, b)}
  defp combine_header_rows(a, b, ""), do: {a, concat_section_header(a, b)}

  # this transforms the rows of each spreadsheet into an Elixir Map,
  # where each key matches a header value, and the value is data
  # from each individual artifact.
  defp transform_artifacts(%{metadata: metadata, headers: headers, rows: rows}) do
    artifacts =
      rows
      |> Enum.reject(fn [zone | _] -> zone == "" end)
      |> Enum.map(fn r ->
        # Combine the List of headers with the list of data from this row
        {_, artifact} =
          Enum.zip(headers, r)
          # Now convert the list of tuples into a map
         |> Enum.map_reduce(%{}, fn {k, v}, acc ->
            # if the value has `\r\n` in it, split into a list of strings
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

  defp split_string_with_multiple_lines(str) when is_binary(str) do
    str
    |> String.split("\r\n")
    |> Enum.reject(fn s -> s == "" end)
    |> case do
      [any] -> any |> String.trim() # return the only element in the list
      any -> any |> Enum.map(&String.trim/1) # return list
    end
  end

  defp split_string_with_multiple_lines(other), do: other

  # Handle unexpected formatting in a given XLSX version of the reference model
  # These numbers are actually in the spreadsheet, but do to Number Formatting
  # options, they are shown as the shortened versions.
  #
  # So these functions exist to revert the floating point numbers
  # back to what the user sees.
  defp special_conversion_hack("2.2000000000000002"), do: "2.2"
  defp special_conversion_hack("2.0099999999999998"), do: "2.01"
  defp special_conversion_hack("10.050000000000001"), do: "10.05"
  defp special_conversion_hack(any), do: any

  defp concat_section_header(section, header) do
    Enum.join([section, header], @section_separator)
  end

  defp split_key_to_section_and_header(key) do
    String.split(key, @section_separator, trim: true, parts: 2)
  end

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

defmodule TmfReferenceModel.Encoder.Json do
  @moduledoc """
  For the output of the Transformer module, convert the map
  into a JSON representation where each Artifact is part of a flat list.
  """

  @doc """
  Given an Elixir Map, with `:metadata` and `:artifacts` keys,
  convert it into it's JSON representation.
  """
  def encode(%{metadata: metadata, artifacts: artifacts}) do
    %{
      :_metadata => metadata,
      artifacts: %{
        :_count => artifacts |> Enum.count(),
        items: artifacts
      }
    }
    |> Jason.encode!(pretty: true)
  end

  def encode(_), do: raise ArgumentError, "Must supply a map with metadata and artifacts keys"

  @doc """
  Encodes the given `artifacts` into JSON using `encode/1

  """
  def encode_and_write(artifacts, input_file_name) do
    output_file = input_file_name |> String.replace(".xlsx", ".json")

    artifacts
    |> encode()
    |> then(&File.write(output_file, &1))

    IO.puts("JSON Output written to: #{output_file}")
  end
end

defmodule TmfReferenceModel.Main do
  @moduledoc """
  Main entry point to the script
  """

  alias TmfReferenceModel.Loader
  alias TmfReferenceModel.Transformer
  alias TmfReferenceModel.Encoder.{Json}

  def main() do
    input_file = "Version-3.2.1-TMF-Reference-Model-v01-Mar-2021.xlsx"

    input_file
    |> Loader.load()
    |> Transformer.transform()
    |> tap( &Json.encode_and_write(&1, input_file))
  end

end

TmfReferenceModel.Main.main()
