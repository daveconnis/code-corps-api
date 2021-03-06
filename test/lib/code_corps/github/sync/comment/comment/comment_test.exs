defmodule CodeCorps.GitHub.Sync.Comment.CommentTest do
  @moduledoc false

  use CodeCorps.DbAccessCase

  import CodeCorps.GitHub.TestHelpers

  alias CodeCorps.{
    Comment,
    GithubComment,
    Repo
  }
  alias CodeCorps.GitHub.Sync.Comment.Comment, as: CommentCommentSyncer

  describe "sync_all/3" do
    @payload load_event_fixture("issue_comment_created")

    test "creates missing, updates existing comments for each project associated with the github repo" do
      %{
        "issue" => %{"number" => number},
        "comment" => %{"id" => comment_github_id, "body" => comment_body} = comment
      } = @payload

      user = insert(:user)
      %{github_repo: github_repo} =
        github_issue = insert(:github_issue, number: number)

      github_comment = insert(:github_comment, github_issue: github_issue, github_id: comment_github_id)

      [%{project: project_1}, %{project: project_2}, %{project: project_3}]
        = insert_list(3, :project_github_repo, github_repo: github_repo)

      task_1 = insert(:task, project: project_1, user: user, github_issue: github_issue, github_repo: github_repo)
      task_2 = insert(:task, project: project_2, user: user, github_issue: github_issue, github_repo: github_repo)
      task_3 = insert(:task, project: project_3, user: user, github_issue: github_issue, github_repo: github_repo)

      comment_1 = insert(:comment, task: task_1, user: user, github_comment: github_comment)

      {:ok, comments} = [task_1, task_2, task_3] |> CommentCommentSyncer.sync_all(github_comment, user, comment)

      assert Enum.count(comments) == 3
      assert Repo.aggregate(Comment, :count, :id) == 3

      task_ids = [task_1, task_2, task_3] |> Enum.map(&Map.get(&1, :id))

      comments |> Enum.each(fn comment ->
        assert comment.user_id == user.id
        assert comment.markdown == comment_body
        assert comment.github_comment_id == github_comment.id
        assert comment.task_id in task_ids
      end)

      comment_ids = comments |> Enum.map(&Map.get(&1, :id))
      assert comment_1.id in comment_ids
    end

    test "fails on validation errors" do
      bad_payload = @payload |> put_in(~w(comment body), nil)

      %{
        "issue" => %{"number" => number},
        "comment" => %{"id" => comment_github_id} = comment
      } = bad_payload

      %{project: project, github_repo: github_repo} =
        insert(:project_github_repo)

      github_issue = insert(:github_issue, number: number, github_repo: github_repo)
      github_comment = insert(:github_comment, github_id: comment_github_id, github_issue: github_issue)
      task = insert(:task, project: project, github_issue: github_issue, github_repo: github_repo)

      %{user: user} = insert(:comment, task: task, github_comment: github_comment)

      {:error, {comments, errors}} =
        [task] |> CommentCommentSyncer.sync_all(github_comment, user, comment)

      assert Enum.count(comments) == 0
      assert Enum.count(errors) == 1
    end
  end

  describe "delete_all/1" do
    test "deletes all the Comment records for a GithubComment" do
      github_comment = insert(:github_comment)
      comments = insert_list(2, :comment, github_comment: github_comment)
      insert(:comment)

      comment_ids = Enum.map(comments, &Map.get(&1, :id))

      {:ok, deleted_comments} =
        github_comment.github_id
        |> CommentCommentSyncer.delete_all()

      assert Enum.count(deleted_comments) == 2
      assert Repo.aggregate(Comment, :count, :id) == 1
      assert Repo.aggregate(GithubComment, :count, :id) == 1

      for deleted_comment <- deleted_comments do
        assert deleted_comment.id in comment_ids
      end
    end

    test "works when there are no Comment records for a GithubComment" do
      github_comment = insert(:github_comment)

      {:ok, deleted_comments} =
        github_comment.github_id
        |> CommentCommentSyncer.delete_all()

      assert Enum.count(deleted_comments) == 0
    end
  end
end
