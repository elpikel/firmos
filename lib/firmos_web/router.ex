defmodule FirmosWeb.Router do
  use FirmosWeb, :router

  import FirmosWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FirmosWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", FirmosWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:firmos, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FirmosWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", FirmosWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{FirmosWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/companies/:id/profile", CompanyLive.Profile, :edit
      live "/companies/:id/activity", CompanyLive.Activity, :index
      live "/companies/:id/plan", CompanyLive.Plan, :show
      live "/companies/:id/site", CompanyLive.Site, :show
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    get "/companies/:id/site/preview", SitePreviewController, :show
    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", FirmosWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{FirmosWeb.UserAuth, :mount_current_scope}] do
      live "/", HomeLive, :index
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
