defmodule RicqchetWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  Components in this module use Tailwind CSS with the brand theme
  ported from the ricqchet-website React application.
  """
  use Phoenix.Component

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  use Gettext, backend: RicqchetWeb.Gettext

  @doc """
  Renders a modal dialog.

  ## Examples

      <.modal id="confirm-modal">
        Are you sure?
        <:actions>
          <.button phx-click="confirm">OK</.button>
        </:actions>
      </.modal>

  JS.push commands may be attached to the `:on_cancel` attribute for
  the caller to react when the modal is closed.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  slot :inner_block, required: true
  slot :actions

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="bg-black/50 fixed inset-0 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-lg p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="relative hidden rounded-xl bg-[hsl(var(--card))] border border-[hsl(var(--border))] p-6 shadow-lg ring-1 ring-black/5 transition"
            >
              <div class="absolute top-4 right-4">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="flex-none p-1 rounded-md hover:bg-[hsl(var(--accent))]"
                  aria-label={gettext("close")}
                >
                  <span class="hero-x-mark-solid h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
                <div :if={@actions != []} class="mt-6 flex justify-end gap-3">
                  {render_slot(@actions)}
                </div>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  attr :kind, :atom, values: [:info, :error], doc: "flash message kind"
  attr :title, :string, default: nil
  attr :rest, :global

  slot :inner_block, doc: "the optional inner block that renders the message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      {@rest}
      class={[
        "fixed top-4 right-4 z-50 w-80 rounded-lg p-4 shadow-lg ring-1 ring-black/5",
        @kind == :info &&
          "bg-brand-500/10 text-brand-600 dark:bg-brand-500/20 dark:text-brand-400",
        @kind == :error &&
          "bg-accent-500/10 text-accent-600 dark:bg-accent-400/20 dark:text-accent-400"
      ]}
    >
      <p :if={@title} class="text-sm font-semibold leading-6">
        <span :if={@kind == :info} class="hero-information-circle-mini mr-1 h-4 w-4" />
        <span :if={@kind == :error} class="hero-exclamation-circle-mini mr-1 h-4 w-4" />
        {@title}
      </p>
      <p class="mt-1 text-sm leading-5">{msg}</p>
      <button type="button" class="absolute top-2 right-2 group" aria-label={gettext("close")}>
        <span class="hero-x-mark-solid h-4 w-4 opacity-50 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a group of flash messages.
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
    <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
    <.flash
      id="client-error"
      kind={:error}
      title={gettext("We can't find the internet")}
      phx-disconnected={show(".phx-client-error #client-error")}
      phx-connected={hide("#client-error")}
      hidden
    >
      {gettext("Attempting to reconnect")}
      <span class="hero-arrow-path-mini ml-1 h-3 w-3 animate-spin" />
    </.flash>
    <.flash
      id="server-error"
      kind={:error}
      title={gettext("Something went wrong!")}
      phx-disconnected={show(".phx-server-error #server-error")}
      phx-connected={hide("#server-error")}
      hidden
    >
      {gettext("Hang in there while we get back on track")}
      <span class="hero-arrow-path-mini ml-1 h-3 w-3 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders a simple form.
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-6">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :variant, :string, default: "primary", values: ~w(primary secondary destructive ghost)
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex items-center justify-center rounded-md px-4 py-2 text-sm font-medium transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(var(--ring))] focus-visible:ring-offset-2",
        "disabled:pointer-events-none disabled:opacity-50",
        "phx-submit-loading:opacity-75",
        variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp variant_class("primary"),
    do:
      "bg-[hsl(var(--primary))] text-[hsl(var(--primary-foreground))] hover:bg-[hsl(var(--primary))]/90"

  defp variant_class("secondary"),
    do:
      "bg-[hsl(var(--secondary))] text-[hsl(var(--secondary-foreground))] hover:bg-[hsl(var(--secondary))]/80"

  defp variant_class("destructive"),
    do:
      "bg-[hsl(var(--destructive))] text-[hsl(var(--destructive-foreground))] hover:bg-[hsl(var(--destructive))]/90"

  defp variant_class("ghost"),
    do: "hover:bg-[hsl(var(--accent))] hover:text-[hsl(var(--accent-foreground))]"

  @doc """
  Renders an input with label and error messages.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <.label :if={@label} for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class={[
          "mt-1 block w-full rounded-md border border-[hsl(var(--input))] bg-[hsl(var(--background))]",
          "px-3 py-2 text-sm shadow-sm",
          "focus:border-[hsl(var(--ring))] focus:outline-none focus:ring-1 focus:ring-[hsl(var(--ring))]",
          @errors != [] && "border-[hsl(var(--destructive))]"
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label :if={@label} for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-1 block w-full rounded-md border border-[hsl(var(--input))] bg-[hsl(var(--background))]",
          "px-3 py-2 text-sm shadow-sm min-h-[80px]",
          "focus:border-[hsl(var(--ring))] focus:outline-none focus:ring-1 focus:ring-[hsl(var(--ring))]",
          @errors != [] && "border-[hsl(var(--destructive))]"
        ]}
        {@rest}
      >{Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class="flex items-center gap-2 text-sm leading-6">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-[hsl(var(--input))] text-[hsl(var(--primary))] focus:ring-[hsl(var(--ring))]"
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div>
      <.label :if={@label} for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          "mt-1 block w-full rounded-md border border-[hsl(var(--input))] bg-[hsl(var(--background))]",
          "px-3 py-2 text-sm shadow-sm",
          "focus:border-[hsl(var(--ring))] focus:outline-none focus:ring-1 focus:ring-[hsl(var(--ring))]",
          @errors != [] && "border-[hsl(var(--destructive))]"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-medium text-[hsl(var(--foreground))]">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Renders form field errors.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-1 flex items-center gap-1 text-sm text-[hsl(var(--destructive))]">
      <span class="hero-exclamation-circle-mini h-4 w-4 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between", @class]}>
      <div>
        <h1 class="text-2xl font-bold tracking-tight text-[hsl(var(--foreground))]">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-1 text-sm text-[hsl(var(--muted-foreground))]">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-3">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  Renders a card container.
  """
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div
      class={[
        "rounded-xl border border-[hsl(var(--border))] bg-[hsl(var(--card))] p-6 shadow-sm",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a stats card for the dashboard.
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :icon, :string, default: nil
  attr :description, :string, default: nil

  def stats_card(assigns) do
    ~H"""
    <.card>
      <div class="flex items-center justify-between">
        <p class="text-sm font-medium text-[hsl(var(--muted-foreground))]">{@label}</p>
        <span :if={@icon} class={[@icon, "h-4 w-4 text-[hsl(var(--muted-foreground))]"]} />
      </div>
      <p class="mt-2 text-2xl font-bold text-[hsl(var(--foreground))]">{@value}</p>
      <p :if={@description} class="mt-1 text-xs text-[hsl(var(--muted-foreground))]">{@description}</p>
    </.card>
    """
  end

  @doc """
  Renders a badge.
  """
  attr :variant, :string, default: "default", values: ~w(default success warning error secondary)
  attr :class, :string, default: nil

  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
      badge_variant(@variant),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_variant("default"),
    do: "bg-[hsl(var(--primary))] text-[hsl(var(--primary-foreground))]"

  defp badge_variant("success"),
    do: "bg-emerald-500/15 text-emerald-600 dark:bg-emerald-500/20 dark:text-emerald-400"

  defp badge_variant("warning"),
    do: "bg-amber-500/15 text-amber-600 dark:bg-amber-500/20 dark:text-amber-400"

  defp badge_variant("error"),
    do: "bg-accent-400/15 text-accent-500 dark:bg-accent-400/20 dark:text-accent-400"

  defp badge_variant("secondary"),
    do: "bg-[hsl(var(--secondary))] text-[hsl(var(--secondary-foreground))]"

  @doc """
  Renders a data table.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  slot :col, required: true do
    attr :label, :string
    attr :class, :string
  end

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm text-left">
        <thead class="border-b border-[hsl(var(--border))]">
          <tr>
            <th :for={col <- @col} class="px-4 py-3 text-xs font-medium text-[hsl(var(--muted-foreground))] uppercase tracking-wider">
              {col[:label]}
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="divide-y divide-[hsl(var(--border))]"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class={["hover:bg-[hsl(var(--accent))]/50", @row_click && "cursor-pointer"]}
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={["px-4 py-3 text-[hsl(var(--foreground))]", col[:class]]}
            >
              {render_slot(col, row)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a sidebar navigation link.
  """
  attr :path, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :current_path, :string, required: true

  def sidebar_link(assigns) do
    active = String.starts_with?(assigns.current_path, assigns.path)
    assigns = assign(assigns, :active, active)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        if(@active,
          do: "bg-[hsl(var(--sidebar-accent))] text-[hsl(var(--sidebar-accent-foreground))]",
          else: "text-[hsl(var(--sidebar-foreground))] hover:bg-[hsl(var(--sidebar-accent))] hover:text-[hsl(var(--sidebar-accent-foreground))]"
        )
      ]}
    >
      <span class={[@icon, "h-5 w-5"]} />
      {@label}
    </.link>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(RicqchetWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(RicqchetWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end
end
