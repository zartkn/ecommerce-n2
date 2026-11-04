# Etapa 1: build com o SDK
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restaura as dependências primeiro para aproveitar o cache de camadas
COPY MsPagamento.csproj .
RUN dotnet restore MsPagamento.csproj

COPY . .
RUN dotnet publish MsPagamento.csproj -c Release -o /app --no-restore

# Etapa 2: imagem final só com o runtime do ASP.NET
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app .

ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER $APP_UID
ENTRYPOINT ["dotnet", "MsPagamento.dll"]
