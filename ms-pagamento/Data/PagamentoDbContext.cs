using Microsoft.EntityFrameworkCore;
using MsPagamento.Domain;

namespace MsPagamento.Data;

/// <summary>Contexto do MySQL próprio do Pagamento (Database per Service).</summary>
public class PagamentoDbContext(DbContextOptions<PagamentoDbContext> options) : DbContext(options)
{
    public DbSet<Pagamento> Pagamentos => Set<Pagamento>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Colunas em snake_case no banco, camelCase no JSON (seção 5)
        modelBuilder.Entity<Pagamento>(e =>
        {
            e.ToTable("pagamentos");
            e.HasKey(p => p.Id);

            e.Property(p => p.Id).HasColumnName("id").HasMaxLength(36);
            e.Property(p => p.PedidoId).HasColumnName("pedido_id").HasMaxLength(36).IsRequired();
            e.Property(p => p.ValorCentavos).HasColumnName("valor_centavos").IsRequired();
            e.Property(p => p.Status).HasColumnName("status").HasMaxLength(20).IsRequired();
            e.Property(p => p.MotivoRecusa).HasColumnName("motivo_recusa").HasMaxLength(50);
            e.Property(p => p.EmailCliente).HasColumnName("email_cliente").HasMaxLength(200).IsRequired();
            e.Property(p => p.ProcessadoEm).HasColumnName("processado_em").HasMaxLength(30).IsRequired();

            // Um pagamento por pedido: é a garantia de idempotência no banco
            e.HasIndex(p => p.PedidoId).IsUnique().HasDatabaseName("uk_pagamentos_pedido_id");
        });
    }
}
