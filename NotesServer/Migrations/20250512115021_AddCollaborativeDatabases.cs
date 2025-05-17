using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NotesServer.Migrations
{
    /// <inheritdoc />
    public partial class AddCollaborativeDatabases : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EndTime",
                table: "ScheduleEntries");

            migrationBuilder.DropColumn(
                name: "IsAllDay",
                table: "ScheduleEntries");

            migrationBuilder.DropColumn(
                name: "StartTime",
                table: "ScheduleEntries");

            migrationBuilder.DropColumn(
                name: "ConnectionString",
                table: "Connections");

            migrationBuilder.AlterColumn<string>(
                name: "Note",
                table: "ScheduleEntries",
                type: "TEXT",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "TEXT");

            migrationBuilder.AlterColumn<string>(
                name: "DynamicFieldsJson",
                table: "ScheduleEntries",
                type: "TEXT",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "TEXT");

            migrationBuilder.AlterColumn<string>(
                name: "Icon",
                table: "PinboardNotes",
                type: "TEXT",
                nullable: false,
                oldClrType: typeof(int),
                oldType: "INTEGER");

            migrationBuilder.AlterColumn<string>(
                name: "Content",
                table: "Notes",
                type: "TEXT",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "TEXT");

            migrationBuilder.AddColumn<string>(
                name: "Images",
                table: "Notes",
                type: "TEXT",
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateTable(
                name: "CollaborativeDatabases",
                columns: table => new
                {
                    Id = table.Column<string>(type: "TEXT", nullable: false),
                    Name = table.Column<string>(type: "TEXT", nullable: false),
                    OwnerId = table.Column<string>(type: "TEXT", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    LastSync = table.Column<DateTime>(type: "TEXT", nullable: false),
                    Version = table.Column<int>(type: "INTEGER", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CollaborativeDatabases", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "DatabaseCollaborators",
                columns: table => new
                {
                    Id = table.Column<string>(type: "TEXT", nullable: false),
                    DatabaseId = table.Column<string>(type: "TEXT", nullable: false),
                    UserId = table.Column<string>(type: "TEXT", nullable: false),
                    Role = table.Column<string>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DatabaseCollaborators", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DatabaseCollaborators_CollaborativeDatabases_DatabaseId",
                        column: x => x.DatabaseId,
                        principalTable: "CollaborativeDatabases",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Notes_FolderId",
                table: "Notes",
                column: "FolderId");

            migrationBuilder.CreateIndex(
                name: "IX_DatabaseCollaborators_DatabaseId",
                table: "DatabaseCollaborators",
                column: "DatabaseId");

            migrationBuilder.AddForeignKey(
                name: "FK_Notes_Folders_FolderId",
                table: "Notes",
                column: "FolderId",
                principalTable: "Folders",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Notes_Folders_FolderId",
                table: "Notes");

            migrationBuilder.DropTable(
                name: "DatabaseCollaborators");

            migrationBuilder.DropTable(
                name: "CollaborativeDatabases");

            migrationBuilder.DropIndex(
                name: "IX_Notes_FolderId",
                table: "Notes");

            migrationBuilder.DropColumn(
                name: "Images",
                table: "Notes");

            migrationBuilder.AlterColumn<string>(
                name: "Note",
                table: "ScheduleEntries",
                type: "TEXT",
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "TEXT",
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "DynamicFieldsJson",
                table: "ScheduleEntries",
                type: "TEXT",
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "TEXT",
                oldNullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "EndTime",
                table: "ScheduleEntries",
                type: "TEXT",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<bool>(
                name: "IsAllDay",
                table: "ScheduleEntries",
                type: "INTEGER",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<DateTime>(
                name: "StartTime",
                table: "ScheduleEntries",
                type: "TEXT",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AlterColumn<int>(
                name: "Icon",
                table: "PinboardNotes",
                type: "INTEGER",
                nullable: false,
                oldClrType: typeof(string),
                oldType: "TEXT");

            migrationBuilder.AlterColumn<string>(
                name: "Content",
                table: "Notes",
                type: "TEXT",
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "TEXT",
                oldNullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ConnectionString",
                table: "Connections",
                type: "TEXT",
                nullable: false,
                defaultValue: "");
        }
    }
}
