# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["realtime-notifications.csproj", "./"]
RUN dotnet restore "realtime-notifications.csproj"
COPY . .
RUN dotnet publish "realtime-notifications.csproj" -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
ENTRYPOINT ["dotnet", "realtime-notifications.dll"]
