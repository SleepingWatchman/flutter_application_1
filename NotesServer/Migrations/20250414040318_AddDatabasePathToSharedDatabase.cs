using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NotesServer.Migrations
{
    /// <inheritdoc />
    public partial class AddDatabasePathToSharedDatabase : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "DatabasePath",
                table: "SharedDatabases",
                type: "TEXT",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AlterColumn<string>(
                name: "Id",
                table: "CollaborationDatabases",
                type: "TEXT",
                nullable: false,
                oldClrType: typeof(int),
                oldType: "INTEGER")
                .OldAnnotation("Sqlite:Autoincrement", true);

            migrationBuilder.CreateIndex(
                name: "IX_SharedDatabases_OwnerId",
                table: "SharedDatabases",
                column: "OwnerId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_SharedDatabases_OwnerId",
                table: "SharedDatabases");

            migrationBuilder.DropColumn(
                name: "DatabasePath",
                table: "SharedDatabases");

            migrationBuilder.AlterColumn<int>(
                name: "Id",
                table: "CollaborationDatabases",
                type: "INTEGER",
                nullable: false,
                oldClrType: typeof(string),
                oldType: "TEXT")
                .Annotation("Sqlite:Autoincrement", true);
        }
    }
}
